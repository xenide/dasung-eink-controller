public struct DisplayMode: Hashable, Sendable, Identifiable {
  public let name: String
  public let value: UInt8

  public var id: UInt8 { value }

  public static func available(forModelVersion version: UInt8) -> [DisplayMode] {
    switch version {
    case 1:
      [
        .init(name: "M1 Web", value: 6), .init(name: "M2 Text", value: 2),
        .init(name: "M3 Image", value: 3), .init(name: "M4 Active", value: 7),
      ]
    case 2:
      [
        .init(name: "M1 Web", value: 6), .init(name: "M2 Text", value: 2),
        .init(name: "M3 Image", value: 3),
      ]
    case 3:
      [
        .init(name: "Auto", value: 5), .init(name: "Text", value: 2),
        .init(name: "Image", value: 3), .init(name: "Active", value: 7),
      ]
    default:
      []
    }
  }
}

public enum FrontLight: UInt8, Sendable, CaseIterable, Identifiable {
  case off = 0
  case cold = 1
  case warm = 2
  case mixed = 3

  public var id: UInt8 { rawValue }

  public var name: String {
    switch self {
    case .off: "Off"
    case .cold: "Cold"
    case .warm: "Warm"
    case .mixed: "Mixed"
    }
  }
}

public struct MonitorState: Equatable, Sendable {
  public static let contrastRange = 1...9
  public static let lightRange = 0...100

  public var contrast: Int?
  public var displayMode: UInt8?
  public var frontLight: FrontLight?
  public var brightness: Int?
  public var temperature: Int?
  public var controllerVersion: UInt8?
  public var modelVersion: UInt8?

  public init() {}

  public var modes: [DisplayMode] {
    modelVersion.map(DisplayMode.available(forModelVersion:)) ?? []
  }

  public var hasFrontLight: Bool {
    controllerVersion.map { $0 & 0xFE == 0x30 } ?? false
  }

  public func mode(after current: UInt8?) -> DisplayMode? {
    guard !modes.isEmpty else { return nil }
    let index = modes.firstIndex { $0.value == current } ?? -1
    return modes[(index + 1) % modes.count]
  }

  public mutating func apply(_ reply: Reply) {
    guard case .report(let raw, let value) = reply, let register = Register(rawValue: raw) else {
      return
    }
    switch register {
    case .contrast: contrast = Int(value)
    case .displayMode: displayMode = value
    case .frontLight: frontLight = FrontLight(rawValue: value)
    case .temperature: temperature = Int(value)
    case .brightness: brightness = Int(value)
    case .controllerVersion: controllerVersion = value
    case .modelVersion: modelVersion = value
    case .refresh, .query: break
    }
  }
}
