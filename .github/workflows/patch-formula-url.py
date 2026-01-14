import os
from pathlib import Path

url = os.environ["URL"]
sha = os.environ["SHA"]
path = Path(os.environ["FORMULA_PATH"])
lines = path.read_text().splitlines()
filtered = []
in_bottle = False
for line in lines:
    stripped = line.lstrip()
    if stripped == "bottle do":
        in_bottle = True
    if stripped == "end" and in_bottle:
        in_bottle = False
    if not in_bottle and stripped.startswith("url "):
        continue
    if not in_bottle and stripped.startswith("sha256 "):
        continue
    filtered.append(line)
out = []
inserted = False
for line in filtered:
    out.append(line)
    if line.lstrip().startswith("homepage ") and not inserted:
        out.append(f'  url "{url}"')
        out.append(f'  sha256 "{sha}"')
        inserted = True
if not inserted:
    raise SystemExit("homepage not found")
text = "\n".join(out)
if path.read_text().endswith("\n"):
    text += "\n"
path.write_text(text)
