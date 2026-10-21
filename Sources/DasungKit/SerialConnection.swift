import Darwin
import Foundation
import Synchronization

public struct SerialError: LocalizedError, Equatable {
  public let operation: String
  public let path: String
  public let code: Int32

  public var errorDescription: String? {
    let reason = String(cString: strerror(code))
    let hint = code == EBUSY ? " Quit any other Paperlike app using the monitor." : ""
    return "Couldn't \(operation) \(path): \(reason).\(hint)"
  }
}

public final class SerialConnection: Sendable {
  private let descriptor: Int32
  private let queue: DispatchQueue
  private let source: any DispatchSourceRead
  private let decoder = Mutex(FrameDecoder())
  private static let commandGap: useconds_t = 80_000

  public init(
    path: String,
    onReply: @escaping @Sendable (Reply) -> Void,
    onClose: @escaping @Sendable () -> Void
  ) throws(SerialError) {
    let descriptor = try Self.openRaw(path: path)
    let queue = DispatchQueue(label: "dasung.serial")
    self.descriptor = descriptor
    self.queue = queue
    self.source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
    source.setEventHandler { [weak self] in self?.drain(onReply: onReply) }
    source.setCancelHandler {
      Darwin.close(descriptor)
      onClose()
    }
    source.activate()
  }

  public func send(_ register: Register, value: UInt8) {
    transmit(Frame.encode(register, value: value))
  }

  public func query(_ register: Register) {
    transmit(Frame.query(register))
  }

  public func close() {
    source.cancel()
  }

  private func transmit(_ frame: Data) {
    queue.async { [self] in
      guard !source.isCancelled else { return }
      let written = frame.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
      if written != frame.count {
        source.cancel()
        return
      }
      usleep(Self.commandGap)
    }
  }

  private func drain(onReply: @Sendable (Reply) -> Void) {
    var chunk = [UInt8](repeating: 0, count: 256)
    let count = read(descriptor, &chunk, chunk.count)
    if count > 0 {
      let replies = decoder.withLock { $0.feed(chunk[0..<count]) }
      replies.forEach(onReply)
    } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
      source.cancel()
    }
  }

  private static func openRaw(path: String) throws(SerialError) -> Int32 {
    let descriptor = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    guard descriptor >= 0 else { throw SerialError(operation: "open", path: path, code: errno) }
    var options = termios()
    guard tcgetattr(descriptor, &options) == 0 else {
      throw closing(descriptor, SerialError(operation: "read settings of", path: path, code: errno))
    }
    cfmakeraw(&options)
    options.c_cflag |= tcflag_t(CLOCAL | CREAD)
    cfsetspeed(&options, speed_t(B115200))
    guard tcsetattr(descriptor, TCSANOW, &options) == 0 else {
      throw closing(descriptor, SerialError(operation: "configure", path: path, code: errno))
    }
    tcflush(descriptor, TCIOFLUSH)
    return descriptor
  }

  private static func closing(_ descriptor: Int32, _ error: SerialError) -> SerialError {
    Darwin.close(descriptor)
    return error
  }
}
