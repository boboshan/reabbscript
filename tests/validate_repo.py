"""Check distributable metadata, text hygiene, and existing catalog paths."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
CATEGORIES = ("Clipboard", "Items Editing", "Markers", "Workflow")
errors = []
actions = sorted(path for category in CATEGORIES for path in (ROOT / category).glob("*.lua"))
for path in actions:
    data = path.read_bytes()
    text = data.decode("utf-8")
    relative = path.relative_to(ROOT).as_posix()
    if b"\r" in data or not data.endswith(b"\n"):
        errors.append(f"{relative}: expected LF and a final newline")
    if any(line.rstrip() != line for line in text.splitlines()):
        errors.append(f"{relative}: trailing whitespace")
    for field in ("description", "version", "author", "about", "changelog"):
        if not re.search(rf"^-- @{field}(?:\s|$)", text, re.MULTILINE):
            errors.append(f"{relative}: missing @{field}")
    if not re.search(r"^-- @version \d+(?:\.\d+)+$", text, re.MULTILINE):
        errors.append(f"{relative}: invalid release version")
    if not path.name.startswith("bbs_"):
        errors.append(f"{relative}: action filename must start with bbs_")

root = ET.parse(ROOT / "index.xml").getroot()
packages = set()
for category in root.findall("category"):
    for package in category.findall("reapack"):
        path = f"{category.attrib['name']}/{package.attrib['name']}"
        if path in packages:
            errors.append(f"{path}: duplicate package")
        packages.add(path)
        if not (ROOT / path).is_file():
            errors.append(f"{path}: catalog entry has no current action")
        for source in package.findall("version/source"):
            if not source.text or not source.text.startswith("https://"):
                errors.append(f"{path}: source URL must use HTTPS")
# New versions enter index.xml when reapack-index scans their commits.
for error in errors:
    print(error, file=sys.stderr)
if errors:
    sys.exit(1)
print(f"Validated {len(actions)} action headers and {len(packages)} published package entries.")
