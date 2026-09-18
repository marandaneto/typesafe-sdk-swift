#!/usr/bin/env python3
"""Run credential-free SDK and example tests via XcodeBuildMCP."""

import json
from pathlib import Path
import re
import subprocess
import sys


def invoke(*arguments):
    process = subprocess.run(
        ["xcodebuildmcp", *arguments, "--output", "json"],
        capture_output=True, text=True, check=False,
    )
    if process.returncode:
        print(process.stdout, end="")
        print(process.stderr, end="", file=sys.stderr)
        raise RuntimeError("XcodeBuildMCP command failed")
    result = json.loads(process.stdout)
    text = "\n".join(item.get("text", "") for item in result.get("content", []))
    print(text)
    if result.get("isError"):
        raise RuntimeError("XcodeBuildMCP reported a tool failure")
    return text


def main():
    root = Path(__file__).resolve().parents[1]
    listing = invoke("simulator", "list", "--enabled")
    match = re.search(r"^- iPhone[^\n]*\(([0-9A-Fa-f-]{36})\)", listing, re.MULTILINE)
    if match is None:
        raise RuntimeError("No available iPhone simulator found")
    result = invoke(
        "simulator", "test",
        "--workspace-path", str(root / "Examples/SupportInbox/SupportInbox.xcworkspace"),
        "--scheme", "SupportInbox",
        "--simulator-id", match.group(1),
        "--derived-data-path", str(root / ".build/simulator-ci"),
    )
    total = re.search(r"Total:\s*(\d+)", result)
    if "Overall Result: Passed" not in result or total is None or int(total.group(1)) == 0:
        raise RuntimeError("Expected a passing, nonempty simulator test run")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        print(f"Simulator tests failed: {error}", file=sys.stderr)
        sys.exit(1)
