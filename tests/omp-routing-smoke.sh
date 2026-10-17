#!/usr/bin/env bash
set -euo pipefail

omp=${OMP_BIN:-$HOME/.nix-profile/bin/omp}
if [[ ! -x $omp && -x /etc/profiles/per-user/$(id -un)/bin/omp ]]; then
  omp=/etc/profiles/per-user/$(id -un)/bin/omp
fi
[[ -x $omp ]] || {
  printf 'FAIL: managed omp launcher unavailable at %s; activate the dotfiles generation first\n' "$omp" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for args in '--model openai/gpt-6.1-sol' '--model=other' '--provider openai' '--config /tmp/direct.yml'; do
  set +e
  # Intentional word splitting into the CLI's distinct arguments.
  # shellcheck disable=SC2086
  "$omp" $args >"$tmp/out" 2>"$tmp/err"
  status=$?
  set -e
  [[ $status == 2 ]] || {
    printf 'FAIL: managed omp accepted override: %s (exit %s)\n' "$args" "$status" >&2
    exit 1
  }
  grep -Fq 'Refusing OMP provider/config override' "$tmp/err" || {
    printf 'FAIL: expected fail-closed override diagnostic for: %s\n' "$args" >&2
    exit 1
  }
done
set +e
"$omp" --model smol --help >"$tmp/smol.out" 2>"$tmp/smol.err"
status=$?
set -e
[[ $status == 0 ]] || {
  printf 'FAIL: managed omp rejected or failed --model smol (exit %s)\n' "$status" >&2
  cat "$tmp/smol.err" >&2
  exit 1
}
grep -Fq 'USAGE' "$tmp/smol.out" || {
  printf 'FAIL: --model smol did not reach OMP as an option (unexpected output)\n' >&2
  cat "$tmp/smol.out" "$tmp/smol.err" >&2
  exit 1
}
printf 'PASS: managed omp routes --model smol to OMP and rejects provider/config and non-smol model overrides\n'
