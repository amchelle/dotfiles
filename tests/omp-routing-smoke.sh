#!/usr/bin/env bash
set -euo pipefail

omp=${OMP_BIN:-$HOME/.nix-profile/bin/omp}
[[ -x $omp ]] || {
  printf 'FAIL: managed omp launcher unavailable at %s; activate the dotfiles generation first\n' "$omp" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for args in '--model openai/gpt-6.1-sol' '--provider openai' '--config /tmp/direct.yml'; do
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
printf 'PASS: managed omp rejects model, provider, and config overrides\n'
