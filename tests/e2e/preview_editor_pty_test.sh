#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <vmarkdown-binary>" >&2
  exit 2
fi

binary="$1"
if [[ ! -x "$binary" ]]; then
  echo "vmarkdown binary is not executable: $binary" >&2
  exit 2
fi
if ! command -v expect >/dev/null 2>&1; then
  echo "expect is required for the preview PTY regression" >&2
  exit 2
fi

test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/vmarkdown-pty.XXXXXX")"
trap 'rm -rf -- "$test_tmp"' EXIT

fixture="$test_tmp/fixture.md"
original="$test_tmp/original.md"
printf '# PTY fixture\n\nstable buffer\n' > "$fixture"
cp "$fixture" "$original"

expect "$(dirname "$0")/preview_editor_pty.exp" "$binary" "$fixture"
cmp "$original" "$fixture"
