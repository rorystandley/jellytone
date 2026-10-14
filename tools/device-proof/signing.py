#!/usr/bin/env python3
"""Select a local wildcard development profile without printing identifiers."""
from __future__ import annotations
import datetime as dt
import hashlib
import os
import plistlib
import shlex
import subprocess
import sys
from pathlib import Path

output = Path(sys.argv[1])
roots = [
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
]
candidates = []
for root in roots:
    for path in root.glob("*") if root.exists() else []:
        try:
            raw = subprocess.check_output(["security", "cms", "-D", "-i", str(path)], stderr=subprocess.DEVNULL)
            profile = plistlib.loads(raw)
        except Exception:
            continue
        entitlements = profile.get("Entitlements", {})
        app_id = entitlements.get("application-identifier", "")
        teams = profile.get("TeamIdentifier") or []
        expires = profile.get("ExpirationDate")
        is_development = bool(entitlements.get("get-task-allow"))
        if not (teams and app_id.endswith(".*") and is_development and expires and expires > dt.datetime.now()):
            continue
        candidates.append((expires, str(teams[0]), str(profile.get("UUID", ""))))

if not candidates:
    print("blocked: no unexpired local wildcard iOS development provisioning profile", file=sys.stderr)
    raise SystemExit(2)

_, team, profile_uuid = max(candidates)
suffix = hashlib.sha256(f"{team}:{profile_uuid}".encode()).hexdigest()[:12]
bundle = f"org.example.phase0.deviceproof.{suffix}"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(
    f"DEVICE_PROOF_TEAM_ID={shlex.quote(team)}\nDEVICE_PROOF_BUNDLE_ID={shlex.quote(bundle)}\n",
    encoding="utf-8",
)
os.chmod(output, 0o600)
print("local signing configuration resolved (identifiers redacted)")
