#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.android"
KEYSTORE_PATH="${KEYSTORE_PATH:-$OUT_DIR/release-keystore.p12}"
SECRETS_PATH="${SECRETS_PATH:-$OUT_DIR/release-keystore-secrets.txt}"
KEY_ALIAS="${KEYSTORE_KEY_ALIAS:-brightness-release}"
DNAME="${KEYSTORE_DNAME:-CN=Brightness Flutter, OU=Release, O=Brightness Flutter, L=Unknown, ST=Unknown, C=US}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

random_hex() {
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

base64_one_line() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w 0 "$1"
  else
    base64 "$1" | tr -d '\n'
  fi
}

if ! command -v keytool >/dev/null 2>&1 &&
  [ "${IN_ANDROID_KEYSTORE_DEVENV:-}" != "1" ] &&
  command -v devenv >/dev/null 2>&1; then
  echo "keytool not found; retrying inside devenv shell."
  exec devenv shell -- env IN_ANDROID_KEYSTORE_DEVENV=1 "$0" "$@"
fi

need keytool
need base64
need od

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

if [ -e "$KEYSTORE_PATH" ]; then
  echo "Refusing to overwrite existing keystore: $KEYSTORE_PATH" >&2
  echo "Move it away or set KEYSTORE_PATH to a new file." >&2
  exit 1
fi

STORE_PASSWORD="${KEYSTORE_STORE_PASSWORD:-$(random_hex)}"
KEY_PASSWORD="${KEYSTORE_KEY_PASSWORD:-$STORE_PASSWORD}"

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype PKCS12 \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias "$KEY_ALIAS" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "$DNAME"

KEYSTORE_BASE64="$(base64_one_line "$KEYSTORE_PATH")"

cat > "$SECRETS_PATH" <<EOF
KEYSTORE_BASE64=$KEYSTORE_BASE64
KEYSTORE_STORE_PASSWORD=$STORE_PASSWORD
KEYSTORE_KEY_PASSWORD=$KEY_PASSWORD
KEYSTORE_KEY_ALIAS=$KEY_ALIAS
EOF
chmod 600 "$KEYSTORE_PATH" "$SECRETS_PATH"

cat <<EOF
Created:
  $KEYSTORE_PATH
  $SECRETS_PATH

Save these GitHub Actions secrets:
  KEYSTORE_BASE64
  KEYSTORE_STORE_PASSWORD
  KEYSTORE_KEY_PASSWORD
  KEYSTORE_KEY_ALIAS

You can view the values with:
  cat "$SECRETS_PATH"
EOF
