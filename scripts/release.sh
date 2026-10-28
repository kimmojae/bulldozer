#!/bin/bash
# 배포용 DMG: release 빌드 → 배포 인증서로 서명 → build/Bulldozer-<버전>.dmg.
# 공증하지 않는다. 받는 사람은 처음 한 번 "그래도 열기"를 누른다(README).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Bulldozer"
# 받는 사람의 손쉬운 사용 권한은 이 인증서에 묶인다. 버전마다 같은 인증서로 서명해야 업데이트해도 권한이 유지된다
export BULLDOZER_SIGN_ID="${BULLDOZER_SIGN_ID:-qr2fa-selfsign}"

./scripts/bundle.sh release

# bundle.sh 는 서명에 실패하면 ad-hoc 으로 넘어간다. 배포본이 ad-hoc 이면 업데이트마다 모두의 권한이 풀려서 여기서 막는다
# (파이프로 grep -q 에 넘기면 grep 이 먼저 끝나 codesign 이 SIGPIPE 로 실패하고, pipefail 에 걸린다)
SIGNATURE="$(codesign -dvv "build/$APP_NAME.app" 2>&1)"
if ! grep -qx "Authority=$BULLDOZER_SIGN_ID" <<<"$SIGNATURE"; then
    echo "❌ '$BULLDOZER_SIGN_ID' 로 서명되지 않았다. 배포하지 않는다" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" packaging/Info.plist)"
DMG="build/$APP_NAME-$VERSION.dmg"

# DMG 안: 앱 + /Applications 바로가기(끌어다 놓아 설치)
STAGING="$(mktemp -d)"
cp -R "build/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -format UDZO -quiet "$DMG"
rm -rf "$STAGING"

# bundle.sh 가 빌드하면서 실행 중인 앱을 끈다. 설치된 게 있으면 다시 켠다
[ -d "/Applications/$APP_NAME.app" ] && open "/Applications/$APP_NAME.app"

echo "✅ $DMG"
