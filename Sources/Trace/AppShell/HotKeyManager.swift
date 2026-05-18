import Carbon
import Foundation

final class HotKeyManager {
    private var copyHotKey: EventHotKeyRef?
    private var deliverHotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var copyAction: (() -> Void)?
    private var deliverAction: (() -> Void)?

    func register(
        copyShortcut: String,
        deliveryShortcut: String,
        copyAction: @escaping () -> Void,
        deliverAction: @escaping () -> Void
    ) {
        unregister()
        self.copyAction = copyAction
        self.deliverAction = deliverAction

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &eventType, pointer, &handler)

        let copyID = EventHotKeyID(signature: Self.signature, id: 1)
        let deliverID = EventHotKeyID(signature: Self.signature, id: 2)
        if let shortcut = HotKeyShortcut(copyShortcut) {
            RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, copyID, GetApplicationEventTarget(), 0, &copyHotKey)
        }
        if let shortcut = HotKeyShortcut(deliveryShortcut) {
            RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, deliverID, GetApplicationEventTarget(), 0, &deliverHotKey)
        }
    }

    deinit {
        unregister()
    }

    private func unregister() {
        if let copyHotKey {
            UnregisterEventHotKey(copyHotKey)
            self.copyHotKey = nil
        }
        if let deliverHotKey {
            UnregisterEventHotKey(deliverHotKey)
            self.deliverHotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
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

private struct HotKeyShortcut {
    let keyCode: UInt32
    let modifiers: UInt32

    init?(_ value: String) {
        let parts = value
            .lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let key = parts.last,
              let keyCode = Self.keyCodes[key] else {
            return nil
        }

        var modifiers: UInt32 = 0
        for modifier in parts.dropLast() {
            switch modifier {
            case "command", "cmd", "⌘":
                modifiers |= UInt32(cmdKey)
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
            case "option", "opt", "alt", "⌥":
                modifiers |= UInt32(optionKey)
            case "control", "ctrl", "⌃":
                modifiers |= UInt32(controlKey)
            default:
                return nil
            }
        }

        guard modifiers != 0 else { return nil }
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A,
        "b": kVK_ANSI_B,
        "c": kVK_ANSI_C,
        "d": kVK_ANSI_D,
        "e": kVK_ANSI_E,
        "f": kVK_ANSI_F,
        "g": kVK_ANSI_G,
        "h": kVK_ANSI_H,
        "i": kVK_ANSI_I,
        "j": kVK_ANSI_J,
        "k": kVK_ANSI_K,
        "l": kVK_ANSI_L,
        "m": kVK_ANSI_M,
        "n": kVK_ANSI_N,
        "o": kVK_ANSI_O,
        "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q,
        "r": kVK_ANSI_R,
        "s": kVK_ANSI_S,
        "t": kVK_ANSI_T,
        "u": kVK_ANSI_U,
        "v": kVK_ANSI_V,
        "w": kVK_ANSI_W,
        "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0,
        "1": kVK_ANSI_1,
        "2": kVK_ANSI_2,
        "3": kVK_ANSI_3,
        "4": kVK_ANSI_4,
        "5": kVK_ANSI_5,
        "6": kVK_ANSI_6,
        "7": kVK_ANSI_7,
        "8": kVK_ANSI_8,
        "9": kVK_ANSI_9
    ]
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
