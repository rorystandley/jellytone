#!/usr/bin/env python3
import re, sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
patterns = [
    (r"\b[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b", "<redacted-device-id>", 0),
    (r"\b[0-9A-F]{40}\b", "<redacted-certificate-hash>", 0),
    (r"\b[A-Z0-9]{10}\b", "<redacted-team-id>", 0),
    (r"https?://(?:\[[^]]+\]|[^/\s:]+)(?::\d+)?(?:/[^\s]*)?", "<redacted-url>", 0),
    (r"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b", "<redacted-address>", 0),
    # Hyphenated device names from build logs, such as "Alexs-iPhone" or "Alex's-iPhone".
    (r"\b[A-Za-z][A-Za-z0-9'.-]{0,40}-iPhone\S*", "<redacted-device-name>", re.IGNORECASE),
]
for pattern, replacement, flags in patterns:
    text = re.sub(pattern, replacement, text, flags=flags)
text = re.sub(r'(?m)^(\s*Signing Identity:\s*).+$', r'\1"<redacted-signing-identity>"', text)
text = re.sub(r'org\.example\.phase0\.deviceproof\.[a-z0-9]+', 'org.example.phase0.deviceproof.<redacted>', text)
Path(sys.argv[2]).write_text(text, encoding="utf-8")
