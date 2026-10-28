import CoreGraphics

/// macOS 27은 노치 오른쪽에 안 들어가는 아이콘을 «(MenuBarAgent의 버튼) 뒤에 넣고, 누르면 노치 왼쪽에 이어서 펼친다(»로 바뀐다).
/// 펼칠 때 넘친 아이콘도 보이도록 이걸 대신 눌러 준다.
enum Overflow {
    /// 열려 있으면 넘친 앱 아이콘이 « 왼쪽(노치 왼쪽)에 놓인다.
    /// - shown: 지금 보이는 아이콘만. 숨긴 아이콘은 엉뚱한 위치를 줘서 열림으로 잘못 읽힌다
    static func isOpen(button: CGRect, shown: [StatusItemInfo]) -> Bool {
        shown.contains { !Sections.systemOwners.contains($0.bundleID) && $0.frame.maxX <= button.minX }
    }
}
