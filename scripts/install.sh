#!/bin/bash
# 상주용 설치: release 빌드 → /Applications 갈아끼우기 → 다시 실행.
# 개발 중 반복 실행이 전제다. 로그인 항목은 처음 한 번만 수동 등록하면 경로가 같아서 유지된다.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Bulldozer"
INSTALL_DIR="/Applications"

# macOS 27 비공개 API로 숨긴다. 그 아래 버전에서는 빌드는 되어도 실행이 거부된다(open 오류 -10825)
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 27 ]; then
    echo "❌ macOS 27 이상이 필요하다(지금: $(sw_vers -productVersion))" >&2
    exit 1
fi

./scripts/bundle.sh release

# bundle.sh 안에서도 pkill 하지만, 그건 build/ 를 만들기 전 시점이다.
# /Applications 사본을 덮어쓰기 직전에 다시 확실히 죽인다.
pkill -x "$APP_NAME" 2>/dev/null || true

# cp -R 만 하면 옛 번들 내용물이 섞여 남는다. 반드시 지우고 복사한다.
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "build/$APP_NAME.app" "$INSTALL_DIR/"

# pkill 직후엔 Launch Services 가 죽은 프로세스를 아직 붙들고 있어 첫 open 이 실패할 수 있다.
open "$INSTALL_DIR/$APP_NAME.app" || (sleep 1; open "$INSTALL_DIR/$APP_NAME.app")

echo "✅ 설치 완료: $INSTALL_DIR/$APP_NAME.app"
