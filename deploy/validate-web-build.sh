#!/usr/bin/env bash
set -euo pipefail

web_root="${1:-/app/build/web}"
source_root="${2:-/app/web}"

fail() {
  echo "ERROR: Web release validation failed: $*" >&2
  exit 1
}

for name in index.html index.js index.pck index.wasm network-config.js mobile-shell.css viewport-bootstrap.js; do
  test -s "${web_root}/${name}" || fail "missing or empty ${name}"
done

viewport_count="$(grep -Eio '<meta[[:space:]]+name="viewport"[[:space:]]+content="[^"]*">' "${web_root}/index.html" | wc -l | tr -d '[:space:]')"
test "${viewport_count}" = "1" || fail "expected exactly one viewport meta tag, found ${viewport_count}"
grep -Eiq '<meta[[:space:]]+name="viewport"[[:space:]]+content="[^"]*viewport-fit=cover[^"]*">' "${web_root}/index.html" \
  || fail "viewport meta is missing viewport-fit=cover"
grep -q '<html lang="vi">' "${web_root}/index.html" || fail 'Web shell language must be lang="vi"'
if grep -Eq '<title>[^<]*(Miá|TÃ¢y|Äáº¡i)' "${web_root}/index.html"; then
  fail 'Web title contains mojibake instead of UTF-8 Vietnamese'
fi

for asset in network-config.js mobile-shell.css viewport-bootstrap.js; do
  grep -Fq "${asset}" "${web_root}/index.html" || fail "index.html does not reference ${asset}"
  cmp -s "${source_root}/${asset}" "${web_root}/${asset}" || fail "build/web/${asset} differs from web/${asset}"
done

echo "PASS: validated Web release at ${web_root}"
