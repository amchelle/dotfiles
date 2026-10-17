#!/usr/bin/env bash
set -euo pipefail
[[ -t 0 ]] || { printf 'Run in a local interactive terminal.\n' >&2; exit 1; }
printf 'Authenticate the next sudo request with Touch ID, not a password.\n'
printf 'If Touch ID is unavailable, cancel; password fallback does not verify this test.\n'
uid=$(sudo -k /usr/bin/id -u)
[[ $uid == 0 ]] || { printf 'FAIL: sudo did not run as root\n' >&2; exit 1; }
printf 'PASS: authenticated sudo ran as root (Touch ID must be observed interactively)\n'
