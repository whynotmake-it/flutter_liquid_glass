#!/usr/bin/env python3
"""Create or locate the one pinned iOS 27 simulator used by the harness."""

import json
import subprocess

NAME = "AppleMatch-iPhone17Pro-iOS27"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"


def simctl(*arguments):
    return subprocess.check_output(["xcrun", "simctl", *arguments], text=True).strip()


data = json.loads(simctl("list", "-j"))
runtimes = [
    runtime
    for runtime in data["runtimes"]
    if runtime["name"].startswith("iOS 27") and runtime.get("isAvailable", False)
]
if not runtimes:
    raise SystemExit("No available iOS 27 runtime. Finish installation, then retry.")
runtime = sorted(runtimes, key=lambda item: item["version"])[-1]
for device in data["devices"].get(runtime["identifier"], []):
    if device["name"] == NAME and device.get("isAvailable", False):
        print(device["udid"])
        break
else:
    print(simctl("create", NAME, DEVICE_TYPE, runtime["identifier"]))
