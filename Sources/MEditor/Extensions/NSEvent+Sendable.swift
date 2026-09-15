import Foundation
#if os(macOS)
import AppKit

/// AppKit 的 `NSEvent` 未声明 `Sendable`，但它是只读、仅主线程派发的事件对象。
/// `NSEvent.addLocalMonitorForEvents` 的 handler 是 `@Sendable`，Swift 6 会报
/// 「conformance of 'NSEvent' to 'Sendable' is unavailable」。按社区通行做法补充
/// `@unchecked Sendable`：前提是所有 NSEvent 访问都发生在主线程（本项目均如此）。
extension NSEvent: @retroactive @unchecked Sendable {}
#endif
