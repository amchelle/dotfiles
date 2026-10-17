#!/usr/bin/env bash
set -euo pipefail
umask 077
origin=${UNDERCLASS_ORIGIN:-http://127.0.0.1:8080}
db=${UNDERCLASS_DATA_DIR:-$HOME/.local/share/underclass}/pool.db
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
request() {
  local path=$1 expected=$2 config=${3:-/dev/null} code
  code=$(curl --silent --show-error --connect-timeout 2 --max-time 5 \
    --config "$config" --output "$tmp/body" --write-out '%{http_code}' "$origin$path") \
    || fail "cannot reach Underclass at $origin"
  [[ $code == "$expected" ]] || fail "$path expected HTTP $expected, received $code"
}
request / 200
request /v1/models 401
request /admin/api/state 401
[[ -f $db && -r $db ]] || fail 'start or repair Underclass: database unavailable'
for key in proxy_key ui_token; do
  value=$(sqlite3 -readonly "$db" "SELECT value FROM config WHERE key = '$key';") \
    || fail 'start or repair Underclass: key query failed'
  [[ -n $value ]] || fail 'start or repair Underclass: key missing'
  # Reject characters that could escape curl's quoted configuration value.
  [[ $value != *[!a-zA-Z0-9_-]* ]] || fail 'unexpected key encoding'
  printf 'header = "Authorization: Bearer %s"\n' "$value" > "$tmp/$key"
  unset value
done
request /v1/models 200 "$tmp/proxy_key"
jq -e '.object == "list" and (.data | type == "array") and all(.data[]; .id | type == "string")' "$tmp/body" > /dev/null \
  || fail 'invalid OpenAI model-list document'
request /admin/api/state 401 "$tmp/proxy_key"
request /v1/models 401 "$tmp/ui_token"
printf 'PASS: loopback HTTP, model catalog, and proxy/admin authentication separation\n'
