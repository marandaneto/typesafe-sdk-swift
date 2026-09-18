#!/usr/bin/env python3
"""Compile DocC Swift examples without executing them or reading credentials."""

import json
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
functions = ["import TypeSafe\n"]
index = 0
for document in sorted((root / "Sources/TypeSafe/TypeSafe.docc").glob("*.md")):
    for source in re.findall(r"```swift\n(.*?)```", document.read_text(), re.DOTALL):
        index += 1
        locals_used = dict.fromkeys(re.findall(r"^let (\w+)", source, re.MULTILINE))
        uses = "\n".join(f"_ = {name}" for name in locals_used)
        functions.append(f'''func example{index}() async throws {{
    let apiKey = "documentation-only-not-a-real-key"
    let client = try TypeSafeClient(apiKey: apiKey)
    _ = client
    do {{
{source}
{uses}
    }}
}}
''')
assert index > 0, "No documentation examples found"
with tempfile.TemporaryDirectory(prefix="typesafe-doc-examples-") as directory:
    package = Path(directory)
    (package / "Package.swift").write_text(f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DocumentationExamples",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: {json.dumps(str(root))})],
    targets: [.target(name: "DocumentationExamples", dependencies: [.product(name: "TypeSafe", package: "typesafe-sdk-swift")])],
    swiftLanguageModes: [.v6]
)
''')
    sources = package / "Sources/DocumentationExamples"
    sources.mkdir(parents=True)
    (sources / "Examples.swift").write_text("\n".join(functions))
    subprocess.run(["swift", "build", "--package-path", str(package), "-Xswiftc", "-warnings-as-errors"], check=True)
print(f"Compiled {index} DocC examples; no API calls executed.")
