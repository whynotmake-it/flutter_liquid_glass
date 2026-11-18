#!/usr/bin/env python3
"""A/B inside one launch on the Pixel 6a: rails, GPU work and thread CPU per
window of a grid bench run (grid.py), flat against glass.

    ab_energy.py run <apk> <out dir>      one launch (hold the pixel lock)
    ab_energy.py report <out dir>...      pairs pooled over runs

The bench flips the renderer every window in ABBA order and logs
`GLASS_BENCH_AB <cell> <A|B> <n> <wall>`. One Perfetto trace holds
the power rails (android.power) and the ftrace events power/gpu_work_period
(GPU active time of each uid) and power/gpu_frequency, and the Mali
hardware counters (gpu.counters, from the system's gpu_counter_producer,
which the run starts: no phone setting changes); an on-device loop reads
the app's thread CPU ticks every 0.5 s. The Mali counters cover the whole
GPU, the compositor included, which both arms share. Each window drops its first
second (the flip settles, the rails' 250 ms poll straddles it). Windows are
paired in order (A0 B1, B2 A3, ...): a pair's difference B - A has the
phone's slow drift taken out, and the spread of the differences is the
noise.
"""
import bisect
import json
import math
import os
import re
import subprocess
import sys
import time

SERIAL = os.environ.get('ANDROID_SERIAL', '26221JEGR12737')
PKG = 'it.whynotmake.apple_liquid_glass_example'
UID_RE = re.compile(r'uid:(\d+)')
SKIP_S = float(os.environ.get("AB_SKIP_S", "1.0"))
# Render stages write ~1 MB/s: the trace streams to its file.
CFG = '''buffers { size_kb: 65536 fill_policy: RING_BUFFER }
write_into_file: true
file_write_period_ms: 2000
data_sources { config { name: "android.power" android_power_config {
  battery_poll_ms: 250 collect_power_rails: true } } }
data_sources { config { name: "linux.ftrace" ftrace_config {
  ftrace_events: "power/gpu_work_period"
  ftrace_events: "power/gpu_frequency" } } }
data_sources { config { name: "gpu.renderstages" } }
data_sources { config { name: "gpu.counters" gpu_counter_config {
  counter_period_ns: 50000000
%s } } }
duration_ms: 900000
'''

# Mali-G78 counters by id (from the producer's descriptor), with the name
# the report prints.
MALI = {
    8: ('Fragment jobs', 'frag jobs'),
    140: ('Tiler jobs', 'tiler jobs'),
    223: ('Tiles', 'tiles'),
    224: ('Killed unchanged tiles', 'killed tiles'),
    65546: ('Pixels', 'pixels'),
    214: ('Fragment warps', 'frag warps'),
    196: ('Fragment active cycles', 'frag active cy'),
    226: ('Non-fragment active cycles', 'nonfrag active cy'),
    139: ('Tiler active cycles', 'tiler active cy'),
    65535: ('GPU cycles', 'gpu cycles'),
    65548: ('Output external read bytes', 'ext read bytes'),
    65553: ('Output external write bytes', 'ext write bytes'),
    65637: ('Texture unit read bytes from external memory',
            'tex ext read bytes'),
}
CFG = CFG % ''.join(f'  counter_ids: {i}\n' for i in MALI)


def adb(*a):
    return subprocess.run(['adb', '-s', SERIAL, *a], capture_output=True,
                          text=True).stdout


def skin():
    v = 99.0
    for line in adb('shell', 'dumpsys', 'thermalservice').splitlines():
        if 'mName=VIRTUAL-SKIN' in line and 'mValue=' in line:
            v = float(line.split('mValue=')[1].split(',')[0])
    return v


def run(apk, out):
    os.makedirs(out, exist_ok=True)
    adb('install', '-r', apk)
    adb('shell', 'am', 'force-stop', PKG)
    uid = int(UID_RE.search(adb('shell', 'pm', 'list', 'packages', '-U',
                                PKG)).group(1))
    while skin() >= float(os.environ.get('COOL_C', '37')):
        time.sleep(15)
    print('skin', skin(), flush=True)
    adb('logcat', '-c')
    open(f'{out}/cfg.txt', 'w').write(CFG)
    adb('push', f'{out}/cfg.txt', '/data/local/tmp/ab.cfg')
    adb('shell', 'rm', '-f', '/data/misc/perfetto-traces/ab.pftrace',
        '/data/local/tmp/ab_ticks.txt')
    adb('shell', 'pidof gpu_counter_producer || '
        '(nohup gpu_counter_producer > /dev/null 2>&1 &)')
    time.sleep(1)
    pid = adb('shell', 'cat /data/local/tmp/ab.cfg | perfetto --txt -c - '
              '-o /data/misc/perfetto-traces/ab.pftrace --background'
              ).strip().splitlines()[-1].strip()
    clock = adb('shell', 'date +%s.%N; cat /proc/uptime').split()
    boot_epoch = float(clock[0]) - float(clock[1])
    time.sleep(2)
    # Android may bring the task back while the phone cools: a start would
    # land in that process, whose log this run cleared.
    adb('shell', 'am', 'force-stop', PKG)
    adb('shell', 'am', 'start', '-n', f'{PKG}/.MainActivity')
    app = ''
    while not app:
        time.sleep(0.5)
        app = adb('shell', 'pidof', PKG).strip()
    # The loop runs on the phone, detached from adb, whose own latency
    # would smear 0.5 s; one cat a tick reads every thread of the app. The
    # UI runs on the main thread (tid = pid), the raster on `1.raster`.
    script = (f'while [ -d /proc/{app} ]; do echo "@ $(date +%s.%N)"; '
              f'cat /proc/{app}/stat /proc/{app}/task/*/stat 2>/dev/null; '
              f'sleep 0.5; done > /data/local/tmp/ab_ticks.txt\n')
    open(f'{out}/ticks.sh', 'w').write(script)
    adb('push', f'{out}/ticks.sh', '/data/local/tmp/ab_ticks.sh')
    adb('shell', 'nohup sh /data/local/tmp/ab_ticks.sh > /dev/null 2>&1 &')
    log = ''
    for _ in range(400):
        time.sleep(5)
        log = adb('logcat', '-d', '-s', 'flutter', '-v', 'raw')
        if 'GLASS_BENCH done' in log or 'Unhandled Exception' in log \
                or not adb('shell', 'pidof', PKG).strip():
            break
    adb('shell', 'kill', '-TERM', pid)
    time.sleep(3)
    adb('pull', '/data/misc/perfetto-traces/ab.pftrace', f'{out}/ab.pftrace')
    adb('pull', '/data/local/tmp/ab_ticks.txt', f'{out}/ticks.txt')
    adb('shell', 'am', 'force-stop', PKG)
    open(f'{out}/log.txt', 'w').write(log)
    json.dump({'boot_epoch': boot_epoch, 'uid': uid, 'skin_end': skin()},
              open(f'{out}/run.json', 'w'))


TP = os.environ.get('TRACE_PROCESSOR', 'trace_processor_shell')
QUERY = '''
select 'r' kind, t.name, c.ts, c.value, 0 dur from counter c
  join counter_track t on c.track_id = t.id where t.type = 'power_rails';
select 'w' kind, s.name, s.ts, extract_arg(t.dimension_arg_set_id, 'uid') value,
  s.dur from slice s join track t on s.track_id = t.id
  where t.type = 'android_gpu_work_period';
select 'f' kind, '' name, c.ts, c.value, 0 dur from counter c
  join counter_track t on c.track_id = t.id where t.type = 'gpu_frequency'
  and extract_arg(t.dimension_arg_set_id, 'gpu') = 0 order by c.ts;
select 'm' kind, t.name, c.ts, c.value, 0 dur from counter c
  join counter_track t on c.track_id = t.id where t.type = 'gpu_counter';
select 's' kind, name, ts, submission_id value, dur from gpu_slice;
'''


def query(trace, sql):
    path = trace + '.sql'
    open(path, 'w').write(sql)
    out = subprocess.run([TP, '-q', path, trace], capture_output=True,
                         text=True).stdout
    rows = []
    for line in out.splitlines():
        if not line.startswith('"') or line.startswith('"kind"'):
            continue
        rows.append([x.strip('"') for x in line.split(',')])
    return rows


def load(out):
    meta = json.load(open(f'{out}/run.json'))
    epoch, uid = meta['boot_epoch'], meta['uid']
    names, rails, work, freq = {}, {}, [], []
    mali = {}
    stages = []
    for kind, name, ts, value, dur in query(f'{out}/ab.pftrace', QUERY):
        t = epoch + int(ts) / 1e9
        if kind == 'r':
            names[name] = name
            rails.setdefault(name, []).append((t, float(value)))
        elif kind == 'w' and value == str(uid):
            d = int(dur) / 1e9
            work.append((t, t + d, d * float(name.lstrip('%')) / 100))
        elif kind == 'f':
            freq.append((t, float(value)))
        elif kind == 'm':
            mali.setdefault(name, []).append((t, float(value)))
        elif kind == 's':
            stages.append((t, name, value, int(dur) / 1e9))
    mali['stages'] = stages
    ticks = []
    stamp, per, first = None, {}, True
    for line in open(f'{out}/ticks.txt'):
        line = line.strip()
        if line.startswith('@ '):
            if stamp is not None:
                ticks.append((stamp, per))
            stamp, per, first = float(line[2:]), {}, True
        elif ')' in line:
            tid = line.split(' ', 1)[0]
            name = line[line.index('(') + 1:line.rindex(')')]
            rest = line[line.rindex(')') + 2:].split()
            cpu = int(rest[11]) + int(rest[12])
            if first:
                per['app'] = cpu
                pid, first = tid, False
            elif tid == pid:
                per['ui'] = cpu
            elif name.endswith('.raster'):
                # A second engine's raster thread may exist idle beside it.
                per['raster'] = per.get('raster', 0) + cpu
            else:
                per[f'{name}:{tid}'] = cpu
    if stamp is not None:
        ticks.append((stamp, per))
    marks = []
    log = open(f'{out}/log.txt').read()
    for m in re.finditer(
            r'GLASS_BENCH_AB (\S+) ([AB]) (\d+) ([\d.]+) ?(\d*)', log):
        marks.append((m.group(1), m.group(2), float(m.group(4)),
                      int(m.group(5) or 0)))
    ends = {m.group(1): (float(m.group(2)), int(m.group(3) or 0)) for m in
            re.finditer(r'GLASS_BENCH_AB_END (\S+) ([\d.]+) ?(\d*)', log)}
    windows = []
    for i, (step, arm, t, frames) in enumerate(marks):
        nxt = marks[i + 1][2:] if i + 1 < len(marks) and \
            marks[i + 1][0] == step else ends.get(step)
        if nxt is not None:
            # Frames come in batches: the rate over the whole window.
            fps = (nxt[1] - frames) / (nxt[0] - t) if nxt[1] else 0
            windows.append({'step': step, 'arm': arm, 'a': t + SKIP_S,
                            'b': nxt[0], 'fps': fps})
    return names, rails, work, freq, ticks, windows, mali


def rail_mw(series, a, b):
    s = sorted(series)

    def at(t):
        for (t0, e0), (t1, e1) in zip(s, s[1:]):
            if t0 <= t <= t1:
                return e0 + (e1 - e0) * (t - t0) / (t1 - t0) if t1 > t0 else e0
        return None
    ea, eb = at(a), at(b)
    return None if ea is None or eb is None else (eb - ea) / 1e3 / (b - a)


GROUPS = {'cpu': ('rails.cpu.',), 'gpu': ('rails.gpu',),
          'mem': ('rails.ddr.', 'rails.memory.', 'rails.system.', 'SLC')}


def freq_at(freq, t):
    i = bisect.bisect_right(freq, (t, math.inf)) - 1
    return freq[i][1] if i >= 0 else 0


def measure(names, rails, work, freq, ticks, w, mali):
    a, b = w['a'], w['b']
    span = b - a
    per = {names.get(k, str(k)): rail_mw(v, a, b) for k, v in rails.items()}
    m = {'total mW': sum(p or 0 for p in per.values())}
    for g, keys in GROUPS.items():
        m[f'{g} mW'] = sum(p or 0 for n, p in per.items()
                           if any(x in n for x in keys))
    active = cycles = 0.0
    for s, e, act in work:
        if e <= a or s >= b or e <= s:
            continue
        share = (min(e, b) - max(s, a)) / (e - s)
        active += act * share
        cycles += act * share * freq_at(freq, (s + e) / 2) * 1e3
    m['fps'] = w['fps']
    m['gpu active ms/s'] = active * 1e3 / span
    m['gpu Mcycles/s'] = cycles / 1e6 / span
    inside = [x for x in ticks if a <= x[0] <= b]
    if len(inside) >= 2:
        (t0, s0), (t1, s1) = inside[0], inside[-1]
        d = {k: (v - s0.get(k, 0)) * 10 / (t1 - t0) for k, v in s1.items()}
        m['ui ms/s'] = d.get('ui', 0)
        m['raster ms/s'] = d.get('raster', 0)
        m['app cpu ms/s'] = d.get('app', 0)
        m['threads'] = d
    fps = w['fps'] or 60
    # A sample holds what the GPU did in the period that ends at it.
    for full, name in MALI.values():
        series = mali.get(full, [])
        total = sum(v for t, v in series if a < t <= b)
        if series:
            m[f'{name}/frame'] = total / span / fps
    inside = [x for x in mali.get('stages', []) if a <= x[0] < b]
    if inside:
        frags = [x for x in inside if x[1] == 'fragment']
        m['passes/frame'] = len(frags) / span / fps
        m['submits/frame'] = len({x[2] for x in inside}) / span / fps
        m['frag stage ms/frame'] = sum(x[3] for x in frags) * 1e3 / span / fps
        m['nonfrag stage ms/frame'] = sum(
            x[3] for x in inside if x[1] == 'non-fragment') * 1e3 / span / fps
        # The pass of a frame that runs longest is the one to the screen.
        longest = {}
        for x in frags:
            longest[x[2]] = max(longest.get(x[2], 0), x[3])
        m['longest pass ms/submit'] = sum(longest.values()) * 1e3 / max(
            len(longest), 1)
    if m.get('frag jobs/frame'):
        m['ui ms/frame'] = m.get('ui ms/s', 0) / fps
        m['raster ms/frame'] = m.get('raster ms/s', 0) / fps
    return m


def report(outs):
    pairs = {}
    for out in outs:
        names, rails, work, freq, ticks, windows, mali = load(out)
        by_step = {}
        for w in windows:
            by_step.setdefault(w['step'], []).append(w)
        for step, ws in by_step.items():
            ms = [(w['arm'], measure(names, rails, work, freq, ticks, w,
                                     mali))
                  for w in ws]
            for i in range(0, len(ms) - 1, 2):
                (x, mx), (y, my) = ms[i], ms[i + 1]
                if {x, y} != {'A', 'B'}:
                    continue
                a, b = (mx, my) if x == 'A' else (my, mx)
                pairs.setdefault(step, []).append((a, b))
    for step, ps in pairs.items():
        print(f'{step}: {len(ps)} pairs')
        print(f'  {"metric":22} {"A":>11} {"B":>11} {"B-A":>10}'
              f' {"+-95%":>9} {"%":>6}')
        for key in ps[0][0]:
            if key == 'threads':
                continue
            d = [b[key] - a[key] for a, b in ps if key in a and key in b]
            av = [a[key] for a, _ in ps if key in a]
            bv = [b[key] for _, b in ps if key in b]
            if len(d) < 2:
                continue
            mean = sum(d) / len(d)
            sd = math.sqrt(sum((x - mean) ** 2 for x in d) / (len(d) - 1))
            ci = 2.0 * sd / math.sqrt(len(d))
            ma = sum(av) / len(av)
            pct = 100 * mean / ma if ma else 0
            print(f'  {key:22} {ma:11.4g} {sum(bv) / len(bv):11.4g}'
                  f' {mean:+10.3g} {ci:9.2g} {pct:+6.1f}')
        busy = {}
        for a, b in ps:
            for k, v in a.get('threads', {}).items():
                busy[k] = busy.get(k, 0) + v / len(ps)
        top = sorted(busy.items(), key=lambda kv: -kv[1])[:8]
        print('  busiest threads (A, ms/s): ' +
              ', '.join(f'{k} {v:.0f}' for k, v in top))


if __name__ == '__main__':
    if sys.argv[1] == 'run':
        run(sys.argv[2], sys.argv[3])
    else:
        report(sys.argv[2:])
