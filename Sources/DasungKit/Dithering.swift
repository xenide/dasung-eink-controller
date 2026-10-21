import Foundation
import IOKit

public struct DitheringError: LocalizedError, Equatable {
  public let code: kern_return_t

  public var errorDescription: String? {
    let reason = String(cString: mach_error_string(code))
    return "Couldn't change display dithering: \(reason) (\(code))."
  }
}

public enum Dithering {
  public static func set(enabled: Bool) throws(DitheringError) {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("IOMobileFramebufferAP")
    let found = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard found == KERN_SUCCESS else { throw DitheringError(code: found) }
    defer { IOObjectRelease(iterator) }
    var failure: kern_return_t = KERN_SUCCESS
    var service = IOIteratorNext(iterator)
    while service != 0 {
      let value: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
      let result = IORegistryEntrySetCFProperty(service, "enableDither" as CFString, value)
      if result != KERN_SUCCESS { failure = result }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }
    guard failure == KERN_SUCCESS else { throw DitheringError(code: failure) }
  }
}
