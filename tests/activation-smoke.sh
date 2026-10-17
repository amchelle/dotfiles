#!/usr/bin/env bash
set -euo pipefail
# -k ignores cached authentication; -n makes a password prompt a hard failure.
sudo -kn /run/current-system/sw/bin/darwin-rebuild --list-generations
if sudo -kn /usr/bin/true 2>/dev/null; then
  printf 'FAIL: unrelated root commands are also passwordless\n' >&2
  exit 1
fi
printf 'PASS: installed rebuild is passwordless; unrelated sudo still requires authentication\n'
