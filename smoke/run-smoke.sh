#!/usr/bin/env bash
#
# End-to-end smoke for the Homebrew-installed keys-on-the-wire.
#
# Proves the INSTALLED artifact actually brokers a credential: starts the
# daemon with a static backend, sends a request carrying a placeholder to a
# bound host (a local echo server aliased upstream.test), and asserts the
# daemon substituted the REAL secret on the wire — and that an unbound host is
# denied. Fully hermetic: no Bitwarden, no external network, no TLS
# (plain-HTTP upstream, which AVP brokers by design), so it is fast and
# deterministic — suitable as a per-release CI gate.
#
# Usage:  smoke/run-smoke.sh
# Env:    KOW_PREFIX  (optional) brew prefix of keys-on-the-wire;
#                     defaults to `brew --prefix keys-on-the-wire`.
#
# Requires upstream.test (and, for the negative test, unbound.test) to resolve
# to 127.0.0.1 — the CI workflow adds them to /etc/hosts; for a local run do:
#   echo "127.0.0.1 upstream.test unbound.test" | sudo tee -a /etc/hosts
#
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PROXY_PORT=14322
ECHO_PORT=8080
PLACEHOLDER="test-PLACEHOLDER-01HXY1234567890ABC"

KOW_PREFIX=${KOW_PREFIX:-$(brew --prefix keys-on-the-wire)}
PY="$KOW_PREFIX/libexec/bin/python"
[ -x "$PY" ] || { echo "FAIL: brew venv python not found at $PY"; exit 1; }

WORK=$(mktemp -d)
SECRETS="$WORK/secrets.yml"
BINDINGS="$WORK/bindings.yaml"
AUDIT="$WORK/audit.jsonl"
PROXY_LOG="$WORK/proxy.log"
ECHO_LOG="$WORK/echo.log"

# A fresh per-run value the echo server must reflect back to us. Varying it
# each run guarantees we are reading a live substitution, not a stale cache.
SECRET_VALUE="smoke-secret-${RANDOM}${RANDOM}${RANDOM}"

pids=()
cleanup() {
    for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

echo "==> workdir $WORK  (proxy=$PROXY_PORT echo=$ECHO_PORT)"

# --- static secret value (never committed; 0600 in a 0700 dir) ---
umask 077
cat > "$SECRETS" <<EOF
secrets:
  TEST_API_KEY: "$SECRET_VALUE"
EOF

# --- render the committed bindings template with per-run paths ---
sed -e "s|__SECRETS_PATH__|$SECRETS|" -e "s|__AUDIT_PATH__|$AUDIT|" \
    "$HERE/bindings.yaml" > "$BINDINGS"
: > "$AUDIT"

# --- local echo server (stands in for the upstream API), aliased upstream.test ---
"$PY" "$HERE/echo_server.py" "$ECHO_PORT" > "$ECHO_LOG" 2>&1 &
pids+=($!)

# --- start the brew-installed daemon against the static config ---
"$PY" -m kow --set avp_config="$BINDINGS" > "$PROXY_LOG" 2>&1 &
pids+=($!)

wait_port() {  # host port name
    local i
    for i in $(seq 1 40); do
        if nc -z "$1" "$2" 2>/dev/null; then return 0; fi
        sleep 0.5
    done
    echo "FAIL: $3 not listening on $1:$2 within 20s"
    return 1
}

wait_port 127.0.0.1 "$ECHO_PORT" "echo server" || { cat "$ECHO_LOG"; exit 2; }
wait_port 127.0.0.1 "$PROXY_PORT" "proxy"       || { tail -40 "$PROXY_LOG"; exit 2; }

echo "==> positive: bound host must receive the REAL secret, not the placeholder"
RESP=$(curl -sS -x "http://127.0.0.1:$PROXY_PORT" \
    -H "Authorization: Bearer $PLACEHOLDER" \
    "http://upstream.test:$ECHO_PORT/broker")
echo "    upstream echoed: $RESP"
if ! grep -q "$SECRET_VALUE" <<<"$RESP"; then
    echo "FAIL: real secret was not injected on the wire"
    echo "--- proxy log ---"; tail -40 "$PROXY_LOG"
    exit 2
fi
if grep -q "$PLACEHOLDER" <<<"$RESP"; then
    echo "FAIL: placeholder leaked to upstream (substitution did not happen)"
    exit 2
fi
echo "    OK: placeholder -> real secret substituted"

echo "==> negative: unbound host must be denied (secret must never be sent there)"
CODE=$(curl -s -o "$WORK/neg.out" -w '%{http_code}' -x "http://127.0.0.1:$PROXY_PORT" \
    -H "Authorization: Bearer $PLACEHOLDER" \
    "http://unbound.test:$ECHO_PORT/nope" || true)
if [ "$CODE" = "200" ] || grep -q "$SECRET_VALUE" "$WORK/neg.out" 2>/dev/null; then
    echo "FAIL: unbound host was not denied (status=$CODE)"
    echo "--- proxy log ---"; tail -40 "$PROXY_LOG"
    exit 2
fi
echo "    OK: unbound host denied (status $CODE)"

echo "==> audit tail:"
tail -5 "$AUDIT" 2>/dev/null | sed 's/^/    /' || true
echo "ALL SMOKE CHECKS PASSED"
