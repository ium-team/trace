import Carbon
import Foundation

final class HotKeyManager {
    private var copyHotKey: EventHotKeyRef?
    private var deliverHotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var copyAction: (() -> Void)?
    private var deliverAction: (() -> Void)?

    func register(copyAction: @escaping () -> Void, deliverAction: @escaping () -> Void) {
        self.copyAction = copyAction
        self.deliverAction = deliverAction

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &eventType, pointer, &handler)

        let copyID = EventHotKeyID(signature: Self.signature, id: 1)
        let deliverID = EventHotKeyID(signature: Self.signature, id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey), copyID, GetApplicationEventTarget(), 0, &copyHotKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_3), UInt32(cmdKey | shiftKey), deliverID, GetApplicationEventTarget(), 0, &deliverHotKey)
    }

    deinit {
        if let copyHotKey { UnregisterEventHotKey(copyHotKey) }
        if let deliverHotKey { UnregisterEventHotKey(deliverHotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    fileprivate func handle(id: UInt32) {
        switch id {
        case 1:
            copyAction?()
        case 2:
            deliverAction?()
        default:
            break
        }
    }

    private static let signature: OSType = {
        let chars = Array("TRCE".utf8)
        return chars.reduce(0) { ($0 << 8) + OSType($1) }
    }()
}

private let hotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handle(id: hotKeyID.id)
    return noErr
}
