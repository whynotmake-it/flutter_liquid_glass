"""One persistent ``flutter run`` session driven by hot reload.

Hot reload is requested with SIGUSR1 and hot restart with SIGUSR2, the
signals documented under ``flutter run --pid-file``. Frame settling is
confirmed through the app-written status file (polled via an injected
``read_status`` callable). A reader thread drains the child's stdout so the
process never blocks on a full pipe.
"""

from __future__ import annotations

import json
import os
import queue
import signal
import subprocess
import threading
import time
from collections import deque

READY_SENTINEL = "APPLE_MATCH_SESSION_READY"
SETTLED_SENTINEL = "APPLE_MATCH_SETTLED"


class SessionError(RuntimeError):
    """The flutter run process failed or never became ready."""


class SettleTimeout(SessionError):
    """The app did not report a settled frame for the requested candidate."""


class SignalReloadTrigger:
    """SIGUSR1/SIGUSR2, documented under ``flutter run --pid-file``."""

    def __init__(self, pid: int, *, kill=None):
        self._pid = pid
        self._kill = kill if kill is not None else os.kill

    def hot_reload(self) -> None:
        self._kill(self._pid, signal.SIGUSR1)

    def hot_restart(self) -> None:
        self._kill(self._pid, signal.SIGUSR2)


class FlutterRunTransport:
    """Owns the ``flutter run`` subprocess and its drained stdout line queue."""

    def __init__(self, command, *, cwd, env, popen=subprocess.Popen):
        # start_new_session puts the flutter wrapper script and its dartvm /
        # frontend_server children in one process group, so terminate() can
        # kill the whole tree — signaling only the wrapper would orphan the
        # real tool process, which then keeps holding the simulator device.
        self._process = popen(
            command,
            cwd=cwd,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        self.lines: queue.Queue = queue.Queue()
        self.tail: deque = deque(maxlen=200)
        self._reader = threading.Thread(target=self._drain, daemon=True)
        self._reader.start()

    def _drain(self) -> None:
        assert self._process.stdout is not None
        for line in self._process.stdout:
            self.tail.append(line)
            self.lines.put(line)

    @property
    def pid(self) -> int:
        return self._process.pid

    def poll(self):
        return self._process.poll()

    def read_line(self, timeout: float):
        try:
            return self.lines.get(timeout=timeout)
        except queue.Empty:
            return None

    def terminate(self) -> None:
        if self.poll() is None:
            try:
                # Graceful quit first: the tool terminates the on-device app.
                self.stdin.write("q")
                self.stdin.flush()
                self._process.wait(timeout=15)
            except Exception:
                self._kill_group()
        for stream in (self._process.stdin, self._process.stdout):
            try:
                if stream is not None:
                    stream.close()
            except Exception:
                pass

    def _kill_group(self) -> None:
        for sig in (signal.SIGTERM, signal.SIGKILL):
            if self.poll() is not None:
                return
            try:
                os.killpg(self._process.pid, sig)
                self._process.wait(timeout=10)
            except Exception:
                pass

    @property
    def stdin(self):
        return self._process.stdin

    def tail_text(self) -> str:
        return "".join(self.tail)


def parse_sentinel(line: str, sentinel: str):
    """Extract the JSON payload of a sentinel line, or None."""
    index = line.find(sentinel)
    if index < 0:
        return None
    try:
        return json.loads(line[index + len(sentinel) :].strip())
    except ValueError:
        return None


class FlutterRunSession:
    """Readiness wait plus reload/settle confirmation with escalation."""

    def __init__(
        self,
        transport,
        trigger,
        *,
        monotonic=time.monotonic,
        sleep=time.sleep,
        poll_interval: float = 0.05,
    ):
        self.transport = transport
        self.trigger = trigger
        self._monotonic = monotonic
        self._sleep = sleep
        self._poll_interval = poll_interval

    @classmethod
    def start(cls, command, *, cwd, env):
        transport = FlutterRunTransport(command, cwd=cwd, env=env)
        return cls(transport, SignalReloadTrigger(transport.pid))

    def wait_ready(self, timeout: float = 900.0) -> dict:
        """Wait for the app session's READY sentinel; returns its payload."""
        deadline = self._monotonic() + timeout
        while self._monotonic() < deadline:
            if self.transport.poll() is not None:
                raise SessionError(
                    "flutter run exited before readiness: "
                    f"{self.transport.tail_text()[-4000:]}"
                )
            line = self.transport.read_line(timeout=0.25)
            if line is None:
                continue
            payload = parse_sentinel(line, READY_SENTINEL)
            if payload is not None:
                return payload
        raise SessionError(
            f"session readiness timed out after {timeout}s: "
            f"{self.transport.tail_text()[-4000:]}"
        )

    def wait_for_output(self, markers, timeout: float = 180.0) -> str:
        """Wait for a tool output line containing one of the markers.

        Used to delay the first SIGUSR1 until the tool has registered its
        signal handlers (before that point the default disposition terminates
        the process). Checks already-drained output first.
        """
        markers = tuple(markers)
        if any(marker in self.transport.tail_text() for marker in markers):
            return ""
        deadline = self._monotonic() + timeout
        while self._monotonic() < deadline:
            if self.transport.poll() is not None:
                raise SessionError(
                    "flutter run exited before becoming reload-ready: "
                    f"{self.transport.tail_text()[-4000:]}"
                )
            line = self.transport.read_line(timeout=0.25)
            if line is not None and any(marker in line for marker in markers):
                return line
        raise SessionError(
            f"flutter run never printed {markers} within {timeout}s: "
            f"{self.transport.tail_text()[-4000:]}"
        )

    def request_settle(
        self,
        *,
        candidate_id: str,
        probe: str,
        serial: int,
        read_status,
        settle_timeout: float = 30.0,
        restart_timeout: float = 90.0,
    ) -> dict:
        """Hot reload, then wait until the app settles this exact candidate.

        Policy: reload, one reload retry, then one hot restart (used only when
        the reload was dropped and the in-app settings update could not run).
        The returned status records which mode produced the settled frame.
        """
        attempts = (
            (self.trigger.hot_reload, "hotReload", settle_timeout),
            (self.trigger.hot_reload, "hotReload", settle_timeout),
            (self.trigger.hot_restart, "hotRestart", restart_timeout),
        )
        for attempt, (fire, mode, timeout) in enumerate(attempts):
            fire()
            deadline = self._monotonic() + timeout
            while self._monotonic() < deadline:
                if self.transport.poll() is not None:
                    raise SessionError(
                        "flutter run exited while waiting for a settled frame: "
                        f"{self.transport.tail_text()[-4000:]}"
                    )
                status = read_status()
                if (
                    status is not None
                    and status.get("state") == "settled"
                    and status.get("candidateId") == candidate_id
                    and status.get("probe") == probe
                    and int(status.get("serial", -1)) >= serial
                ):
                    status["reloadMode"] = mode
                    status["reloadRetries"] = attempt
                    return status
                self._sleep(self._poll_interval)
        raise SettleTimeout(
            f"no settled frame for {candidate_id}/{probe} serial {serial} "
            "after hot reload, retry, and hot restart"
        )

    def terminate(self) -> None:
        self.transport.terminate()
