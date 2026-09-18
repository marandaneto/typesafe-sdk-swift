#!/usr/bin/env python3
"""Launch the installed Debug sample with a local, unbundled API key."""

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys


def load_key(path):
    if not path.is_file():
        raise ValueError("Create the repository .env file with TYPESAFE_API_KEY first.")
    for line in path.read_text().splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[7:]
        name, separator, value = line.partition("=")
        if separator and name.strip() in {"TYPESAFE_API_KEY", "apiKey"}:
            parts = shlex.split(value, comments=True)
            if len(parts) != 1 or not parts[0] or any(c in parts[0] for c in "\r\n\x00"):
                raise ValueError("TYPESAFE_API_KEY must contain one nonempty value.")
            return parts[0]
    raise ValueError("The repository .env must define TYPESAFE_API_KEY.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-id", required=True)
    args = parser.parse_args()
    key = load_key(Path(__file__).resolve().parents[2] / ".env")
    bundle_id = "com.marandaneto.typesafe.SupportInbox"
    environment = {**os.environ, "NODE_NO_WARNINGS": "1"}
    subprocess.run(
        ["xcodebuildmcp", "simulator", "stop", "--simulator-id", args.simulator_id, "--bundle-id", bundle_id],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=environment, check=False,
    )
    payload = {"simulatorId": args.simulator_id, "bundleId": bundle_id, "env": {"TYPESAFE_API_KEY": key}}
    result = subprocess.run(
        ["xcodebuildmcp", "simulator", "launch-app", "--simulator-id", args.simulator_id,
         "--bundle-id", bundle_id, "--json", json.dumps(payload)],
        capture_output=True, text=True, env=environment, check=False,
    )
    output = (result.stdout + result.stderr).replace(key, "<redacted>")
    print(output, end="")
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError):
        print("Launch failed. Check .env contains TYPESAFE_API_KEY and xcodebuildmcp is installed.", file=sys.stderr)
        sys.exit(1)
