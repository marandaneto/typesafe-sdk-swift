#!/usr/bin/env python3
"""Build the DocC archive and fail on tool errors or a missing archive."""

import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
output = root / ".build/documentation"
process = subprocess.run([
    "xcodebuildmcp", "macos", "build",
    "--workspace-path", str(root / "Examples/SupportInbox/SupportInbox.xcworkspace"),
    "--scheme", "TypeSafe", "--derived-data-path", str(output),
    "--json", json.dumps({"extraArgs": ["docbuild", "OTHER_DOCC_FLAGS=--warnings-as-errors"]}),
    "--output", "json",
], capture_output=True, text=True, check=True)
result = json.loads(process.stdout)
print("\n".join(item.get("text", "") for item in result.get("content", [])))
if result.get("isError") or not list(output.rglob("TypeSafe.doccarchive")):
    raise SystemExit("DocC build failed or no archive was produced")
