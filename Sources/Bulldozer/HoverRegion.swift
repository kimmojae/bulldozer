import CoreGraphics

/// 호버 판정에 필요한 화면 한 개의 기하. NSScreen에서 뽑아 만든다(AppKit 없이 테스트하려고).
struct ScreenGeometry: Equatable {
    var frame: CGRect          // 전역 좌표 (NSScreen.frame)
    var notchRight: CGRect?    // NSScreen.auxiliaryTopRightArea 그대로 (전역 좌표, 실측). 노치 없으면 nil
    var menuBarHeight: CGFloat
}

/// 마우스가 "메뉴바 위"에 있는지. 왼쪽 앱 메뉴(파일, 편집…)를 쓸 때 펼쳐지지 않게
/// 노치 화면은 노치 오른쪽만, 노치 없는 화면은 오른쪽 절반만 본다.
enum HoverRegion {
    static func rect(for screen: ScreenGeometry) -> CGRect {
        // `if let x = 옵셔널`: 값이 있을 때만 꺼내서 x로 쓴다
        // 이미 전역 좌표라 화면 원점을 더하지 않는다. 더하면 내장 화면이 주 화면이 아닐 때 영역이 화면 밖으로 간다
        if let notch = screen.notchRight { return notch }
        let f = screen.frame
        return CGRect(x: f.midX, y: f.maxY - screen.menuBarHeight,
                      width: f.maxX - f.midX, height: screen.menuBarHeight)
    }

    /// 빈 곳: 영역에서 상태 아이콘(시계, Wi-Fi…) 자리를 뺀 왼쪽 부분. 접혀 있을 때는 여기서만 펼친다.
    /// 상태 아이콘은 오른쪽 정렬이라 오른쪽 끝에서 잰 폭(statusWidth)이 모든 화면에서 같다.
    /// 폭을 모르거나 빈 곳이 너무 좁으면(노치 오른쪽이 꽉 참) 전체 영역을 쓴다. 펼칠 방법이 없어지면 안 된다
    static func emptyRect(for screen: ScreenGeometry, statusWidth: CGFloat?) -> CGRect {
        let full = rect(for: screen)
        guard let statusWidth else { return full }
        // 첫 아이콘과 바로 붙어 있으면 아이콘을 누르러 갈 때도 펼쳐지므로 조금 띄운다
        let right = screen.frame.maxX - statusWidth - 4
        guard right - full.minX >= minimumEmptyWidth else { return full }
        return CGRect(x: full.minX, y: full.minY, width: right - full.minX, height: full.height)
    }

    private static let minimumEmptyWidth: CGFloat = 24

    /// - statusWidth: 주면 빈 곳만, nil이면 전체 영역으로 판정한다
    static func contains(_ point: CGPoint, screens: [ScreenGeometry], statusWidth: CGFloat? = nil) -> Bool {
        screens.contains { screen in
            let r = emptyRect(for: screen, statusWidth: statusWidth)
            // CGRect.contains는 maxX/maxY를 빼므로, 맨 위 모서리(y == maxY)도 들어가게 직접 비교한다
            return point.x >= r.minX && point.x <= r.maxX && point.y >= r.minY && point.y <= r.maxY
        }
    }
}
