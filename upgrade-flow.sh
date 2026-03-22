#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version-tag>" >&2
  echo "Example: $0 v0.11.0" >&2
  exit 1
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^v[0-9]+(\.[0-9]+)*([.-][0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "Expected a version tag like v0.11.0, got: $VERSION" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_PATH="$SCRIPT_DIR/com.flow_browser.flow.yml"
TARBALL_URL="https://github.com/MultiboxLabs/flow-browser/archive/refs/tags/${VERSION}.tar.gz"
TARBALL_PATH="$(mktemp)"

cleanup() {
  rm -f "$TARBALL_PATH"
}
trap cleanup EXIT

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "Manifest not found: $MANIFEST_PATH" >&2
  exit 1
fi

CURRENT_VERSION="$(
  python3 - "$MANIFEST_PATH" <<'PY'
import pathlib
import re
import sys

manifest = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(
    r"MultiboxLabs/flow-browser/archive/refs/tags/(v[^/\s]+)\.tar\.gz",
    manifest,
)
if not match:
    raise SystemExit("Could not parse flow-browser version from manifest")
print(match.group(1))
PY
)"

echo "Downloading ${TARBALL_URL}..."
curl -fsSL "$TARBALL_URL" -o "$TARBALL_PATH"

if command -v sha256sum >/dev/null 2>&1; then
  SHA256="$(sha256sum "$TARBALL_PATH" | awk '{print $1}')"
else
  SHA256="$(shasum -a 256 "$TARBALL_PATH" | awk '{print $1}')"
fi

python3 - "$MANIFEST_PATH" "$VERSION" "$SHA256" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
sha256 = sys.argv[3]
text = path.read_text(encoding="utf-8")
pattern = (
    r"(      - type: archive\r?\n"
    r"        url: https://github.com/MultiboxLabs/flow-browser/archive/refs/tags/)"
    r"v[^\r\n ]+\.tar\.gz\r?\n"
    r"(        sha256: )[a-f0-9]{64}"
)

def replace(match: re.Match[str]) -> str:
    return f"{match.group(1)}{version}.tar.gz\n{match.group(2)}{sha256}"

updated, count = re.subn(pattern, replace, text, count=1)
if count != 1:
    raise SystemExit(f"Expected 1 manifest replacement, got {count}")

path.write_text(updated, encoding="utf-8")
PY

echo "Updated manifest: ${CURRENT_VERSION} -> ${VERSION}"
echo "Regenerating generated-sources.json..."
"$SCRIPT_DIR/generate-sources.sh" "$VERSION"
echo "Upgrade complete."
