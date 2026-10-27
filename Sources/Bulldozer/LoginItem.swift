import ServiceManagement

/// 로그인 시 실행. macOS 13+의 SMAppService는 이 앱 번들 자체를 로그인 항목으로 등록한다
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Bulldozer: 로그인 항목 변경 실패 \(error)")
        }
    }
}
