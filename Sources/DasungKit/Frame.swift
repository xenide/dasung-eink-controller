import Foundation

public enum Register: UInt8, Sendable, CaseIterable {
  case contrast = 0x01
  case displayMode = 0x02
  case refresh = 0x03
  case frontLight = 0x07
  case temperature = 0x08
  case brightness = 0x09
  case query = 0x0A
  case controllerVersion = 0x10
  case modelVersion = 0x13
}

public enum Reply: Equatable, Sendable {
  case acknowledged(UInt8)
  case report(register: UInt8, value: UInt8)
}

public enum Frame {
  public static let length = 24
  static let header = Array("5FF5".utf8)
  static let trailer = Array("A0FA".utf8)
  static let acknowledgement: UInt8 = 0xF0

  public static func encode(_ register: Register, value: UInt8) -> Data {
    let text = "5FF5" + hex(register.rawValue) + hex(value) + String(repeating: "0", count: 12)
    return Data((text + "A0FA").utf8)
  }

  public static func query(_ register: Register) -> Data {
    encode(.query, value: register.rawValue)
  }

  static func decode(_ frame: ArraySlice<UInt8>) -> Reply? {
    let ascii = Array(frame)
    guard ascii.count == length, ascii.starts(with: header), ascii.suffix(4).elementsEqual(trailer)
    else { return nil }
    let fields = (0..<4).compactMap { parseByte(ascii[4 + $0 * 2], ascii[5 + $0 * 2]) }
    guard fields.count == 4 else { return nil }
    switch (fields[0], fields[1]) {
    case (acknowledgement, Register.query.rawValue):
      return .report(register: fields[2], value: fields[3])
    case (acknowledgement, let command):
      return .acknowledged(command)
    case (let register, let value):
      return .report(register: register, value: value)
    }
  }

  private static func hex(_ byte: UInt8) -> String {
    String(format: "%02X", byte)
  }

  private static func parseByte(_ high: UInt8, _ low: UInt8) -> UInt8? {
    UInt8(String(decoding: [high, low], as: UTF8.self), radix: 16)
  }
}

public struct FrameDecoder: Sendable {
  private var buffer: [UInt8] = []

  public init() {}

  public mutating func feed(_ bytes: some Sequence<UInt8>) -> [Reply] {
    buffer.append(contentsOf: bytes)
    var replies: [Reply] = []
    while let start = headerStart() {
      buffer.removeFirst(start)
      guard buffer.count >= Frame.length else { return replies }
      if let reply = Frame.decode(buffer.prefix(Frame.length)) {
        replies.append(reply)
        buffer.removeFirst(Frame.length)
      } else {
        buffer.removeFirst()
      }
    }
    buffer = Array(buffer.suffix(Frame.header.count - 1))
    return replies
  }

  private func headerStart() -> Int? {
    let width = Frame.header.count
    guard buffer.count >= width else { return nil }
    return (0...(buffer.count - width)).first {
      buffer[$0..<($0 + width)].elementsEqual(Frame.header)
    }
  }
}
