import Carbon.HIToolbox

enum Shortcut: UInt32, CaseIterable {
  case refresh = 1
  case nextMode
  case contrastUp
  case contrastDown
  case lightUp
  case lightDown

  static let modifiers = UInt32(controlKey | optionKey | cmdKey)
  static let modifierSymbols = "⌃⌥⌘"

  var keyCode: Int {
    switch self {
    case .refresh: kVK_ANSI_R
    case .nextMode: kVK_ANSI_M
    case .contrastUp: kVK_ANSI_Equal
    case .contrastDown: kVK_ANSI_Minus
    case .lightUp: kVK_ANSI_RightBracket
    case .lightDown: kVK_ANSI_LeftBracket
    }
  }

  var key: String {
    switch self {
    case .refresh: "R"
    case .nextMode: "M"
    case .contrastUp: "="
    case .contrastDown: "−"
    case .lightUp: "]"
    case .lightDown: "["
    }
  }

  var label: String {
    switch self {
    case .refresh: "Refresh screen"
    case .nextMode: "Next display mode"
    case .contrastUp: "Contrast up"
    case .contrastDown: "Contrast down"
    case .lightUp: "Front light brighter"
    case .lightDown: "Front light dimmer"
    }
  }
}

@MainActor
final class HotKeys {
  private var actions: [UInt32: @MainActor () -> Void] = [:]
  private var handler: EventHandlerRef?
  private var registered: [EventHotKeyRef] = []
  private static let signature: OSType = 0x4453_4E47

  private(set) var failures: [Shortcut] = []

  func register(_ bindings: [Shortcut: @MainActor () -> Void]) {
    guard installHandlerIfNeeded() == noErr else {
      failures = Array(bindings.keys)
      return
    }
    for (shortcut, action) in bindings {
      var reference: EventHotKeyRef?
      let identifier = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
      let status = RegisterEventHotKey(
        UInt32(shortcut.keyCode), Shortcut.modifiers, identifier, GetApplicationEventTarget(), 0,
        &reference)
      guard status == noErr, let reference else {
        failures.append(shortcut)
        continue
      }
      registered.append(reference)
      actions[shortcut.rawValue] = action
    }
  }

  private func installHandlerIfNeeded() -> OSStatus {
    guard handler == nil else { return noErr }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
    let context = Unmanaged.passUnretained(self).toOpaque()
    return InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard status == noErr else { return status }
        let id = identifier.id
        MainActor.assumeIsolated {
          Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().actions[id]?()
        }
        return noErr
      }, 1, &spec, context, &handler)
  }
}
