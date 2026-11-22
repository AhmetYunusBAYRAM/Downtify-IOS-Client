#!/usr/bin/env python3
"""Select an available simulator by device family and iOS runtime for CI."""
import json
import os
import subprocess
import sys

family = sys.argv[1]
runtime_version = sys.argv[2]
if family not in ("iPhone", "iPad"):
    raise SystemExit(f"Unsupported device family: {family}")

devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
))["devices"]
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + runtime_version.replace(".", "-")
candidates = [device for device in devices.get(runtime, [])
              if device.get("isAvailable") and device["name"].startswith(family)]
if not candidates:
    raise SystemExit(f"No available {family} simulator for iOS {runtime_version} ({runtime})")
selected = candidates[0]
print(f"Selected {selected['name']} on iOS {runtime_version}", file=sys.stderr)
with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
    env.write(f"DOWNTIFY_SIM_DESTINATION=platform=iOS Simulator,id={selected['udid']}\n")
