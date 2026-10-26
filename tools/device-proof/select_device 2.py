#!/usr/bin/env python3
import json, re, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
matches = []
def walk(value):
    if isinstance(value, dict):
        text = json.dumps(value)
        if "iPhone 13" in text and "available" in text.lower():
            for item in value.values():
                if isinstance(item, str) and re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", item):
                    matches.append(item)
        for child in value.values(): walk(child)
    elif isinstance(value, list):
        for child in value: walk(child)
walk(data)
if not matches:
    print("blocked: no available paired iPhone 13", file=sys.stderr)
    raise SystemExit(2)
print(matches[0])
