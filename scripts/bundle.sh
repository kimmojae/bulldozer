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
SIGN_ID="${BULLDOZER_SIGN_ID:-qr2fa-selfsign}"
if ! codesign --force --sign "$SIGN_ID" "$APP"; then
    echo "⚠️  '$SIGN_ID' 로 서명 실패 → ad-hoc 서명. 손쉬운 사용 권한이 풀려 아무것도 숨기지 않는다." >&2
    echo "    키체인 확인 창이 뜨면 '항상 허용'을 누르고 다시 설치한다." >&2
    codesign --force --sign - "$APP"
fi

echo "built $APP"
