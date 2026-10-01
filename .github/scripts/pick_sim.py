#!/usr/bin/env python3
"""Print the UDID of an available iPhone or iPad simulator (newest iOS runtime >= 16).

Usage: pick_sim.py iphone|ipad
Parses `xcrun simctl list devices available -j`; never hardcodes device names.
"""
import json
import re
import subprocess
import sys

kind = sys.argv[1].lower()
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
devices = json.loads(raw)["devices"]


def runtime_version(key):
    m = re.search(r"iOS-(\d+)-(\d+)", key)
    return (int(m.group(1)), int(m.group(2))) if m else None


def score(name):
    # Prefer standard models over SE / mini / Pro Max style outliers.
    s = 0
    if "SE" in name or "mini" in name or "Plus" in name:
        s -= 5
    if "Pro Max" in name:
        s -= 2
    if "Pro" in name:
        s += 1
    return s


candidates = []
for runtime, devs in devices.items():
    ver = runtime_version(runtime)
    if not ver or ver[0] < 16:
        continue
    for d in devs:
        if not d.get("isAvailable", True):
            continue
        name = d["name"]
        if kind == "iphone" and name.startswith("iPhone"):
            candidates.append((ver, score(name), name, d["udid"]))
        elif kind == "ipad" and name.startswith("iPad"):
            candidates.append((ver, score(name), name, d["udid"]))

if not candidates:
    sys.stderr.write(f"No available {kind} simulator found\n")
    sys.exit(1)

candidates.sort(key=lambda c: (c[0], c[1], c[2]), reverse=True)
ver, _, name, udid = candidates[0]
sys.stderr.write(f"Selected {name} (iOS {ver[0]}.{ver[1]}) {udid}\n")
print(udid)
