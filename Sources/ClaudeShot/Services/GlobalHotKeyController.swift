import Carbon.HIToolbox
import Foundation

// Ported 1:1 from Agent Swarm.
final class GlobalHotKeyController {
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentHotKey: AppshotHotKey?

    init() {
        installEventHandler()
    }

    deinit {
        unregisterHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ hotKey: AppshotHotKey) {
        guard currentHotKey != hotKey else { return }
        unregisterHotKey()
        installEventHandler()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard status == noErr else {
            NSLog("ClaudeShot global appshot hotkey registration failed: \(status)")
            currentHotKey = nil
            return
        }

        hotKeyRef = newHotKeyRef
        currentHotKey = hotKey
    }

    func handleHotKeyEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == Self.signature, hotKeyID.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor [onPressed] in
            onPressed?()
        }
        return noErr
    }

    private func installEventHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status != noErr {
            NSLog("ClaudeShot global hotkey handler install failed: \(status)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentHotKey = nil
    }

    private static let signature: OSType = {
        let scalars = Array("CSHT".utf8)
        return OSType(scalars[0]) << 24
            | OSType(scalars[1]) << 16
            | OSType(scalars[2]) << 8
            | OSType(scalars[3])
    }()
}

private let globalHotKeyHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
    return controller.handleHotKeyEvent(eventRef)
}
