#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Bulldozer"
APP="build/Bulldozer.app"

pkill -x Bulldozer 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Bulldozer"
cp packaging/Info.plist "$APP/Contents/Info.plist"

# 손쉬운 사용 권한(TCC)은 서명에 묶인다. ad-hoc 서명은 빌드마다 바뀌어 권한을 매번 다시 줘야 하므로
# 고정 인증서로 서명한다. 실패하면 경고하고 ad-hoc 으로 서명한다
SIGN_ID="${BULLDOZER_SIGN_ID:-Bulldozer Local Signing}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 기본 인증서가 없으면 이 Mac 전용 자체 서명 인증서를 로그인 키체인에 만든다(처음 한 번).
# 신뢰 설정은 필요 없다 — 신뢰되지 않은 인증서로도 서명되고, 권한은 인증서 자체에 묶인다(실측)
if [ -z "${BULLDOZER_SIGN_ID:-}" ] && ! security find-certificate -c "$SIGN_ID" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    echo "🔑 '$SIGN_ID' 인증서를 로그인 키체인에 만든다"
    TMP="$(mktemp -d)"
    # 시스템 openssl(LibreSSL)을 쓴다. OpenSSL 3 의 p12 는 security import 가 못 읽는다
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$SIGN_ID" \
        -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:bulldozer
    # -T: codesign 이 키를 쓸 때 키체인 확인 창을 띄우지 않게 미리 허락한다
    security import "$TMP/id.p12" -k "$LOGIN_KEYCHAIN" -P bulldozer -T /usr/bin/codesign
    rm -rf "$TMP"
fi

if ! codesign --force --sign "$SIGN_ID" "$APP"; then
    echo "⚠️  '$SIGN_ID' 로 서명 실패 → ad-hoc 서명. 손쉬운 사용 권한이 풀려 아무것도 숨기지 않는다." >&2
    echo "    키체인 확인 창이 뜨면 '항상 허용'을 누르고 다시 설치한다." >&2
    codesign --force --sign - "$APP"
fi

echo "built $APP"
