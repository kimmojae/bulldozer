# Bulldozer

macOS 27 메뉴바 아이콘 숨기기. 평소엔 숨겨 두고, 메뉴바에 마우스를 올리면 보인다.

```
[always hidden] ‖  [hidden]  |  [항상 보임]  [시스템 아이콘]
```

- **접힘**: 항상 보임 + 시스템 아이콘만
- **호버**: 메뉴바 빈 곳(앱 메뉴와 상태 아이콘 사이, 노치 화면은 노치 오른쪽)에 마우스를 올리면 hidden까지. 시계·Wi-Fi 같은 아이콘 위에서는 펼치지 않는다
- **`|` 클릭**: always hidden까지 전부(`‖`가 나타난다). 다시 클릭하면 hidden까지로 돌아온다
- **`|` 우클릭**: Show on Hover / Show on Click, Launch at Login, Quit Bulldozer

**Show on Click** 모드: 접혀 있어도 `|`가 보이고, `|`를 누를 때마다 한 단계씩 더 펼친다(hidden → always hidden → 접힘). 메뉴바 밖을 클릭하면 접힌다.

두 모드 모두 규칙은 같다: **`|` 클릭 = 하나 더 보기.**

## 설치

```bash
./scripts/install.sh    # release 빌드 → /Applications/Bulldozer.app 교체 → 실행
swift test              # 순수 로직 테스트
```

손쉬운 사용 권한은 앱 서명에 묶여서, 재설치해도 풀리지 않게 고정 인증서로 서명한다.
기본은 로컬 자체 서명 인증서 `qr2fa-selfsign`이고, `BULLDOZER_SIGN_ID=<인증서 이름> ./scripts/install.sh`로 바꾼다.
서명에 실패하면 ad-hoc으로 서명하고 경고한다(그러면 권한이 풀려 아무것도 숨기지 않는다).

처음 실행하면 **손쉬운 사용** 권한을 요청한다(시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용). 허용한 뒤 앱을 다시 켠다.
`/Applications`에서 실행해야 한다.

## 사용법

1. 펼친 상태에서 ⌘-드래그로 아이콘을 옮긴다. `|` 왼쪽 = hidden, 오른쪽 = 항상 보임. 놓으면 바로 반영된다.
2. always hidden으로 옮기거나 꺼내려면 `|`를 클릭해 `‖`까지 전부 펼친 뒤 옮긴다. `‖` 왼쪽 = always hidden.

새로 켜진 앱의 아이콘은 hidden으로 시작한다. 숨김은 앱 단위이고, 시계·Wi-Fi 같은 시스템 아이콘은 숨길 수 없다.

## 주의

macOS 27의 비공개 API(`MenuBarClientCore`)를 쓴다. macOS 업데이트로 깨질 수 있고, 깨지면 아무것도 숨기지 않는다.

## 참고

macOS 27 숨김 방식(비공개 API, 메뉴바 아이콘 읽기)은 [Hidden Bar](https://github.com/dwarvesf/hidden)를 참고했다.
