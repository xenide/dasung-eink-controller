import Foundation
import IOKit

public enum PortLocator {
  static let vendorID = 0x1A86
  static let productID = 0x7523
  static let serialClass = "IOSerialBSDClient"

  public static func candidatePaths() -> [String] {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching(serialClass)
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var paths: [String] = []
    var service = IOIteratorNext(iterator)
    while service != 0 {
      if isMonitorBridge(service), let path = property(service, "IOCalloutDevice") as? String {
        paths.append(path)
      }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }
    return paths.sorted()
  }

  private static func isMonitorBridge(_ service: io_object_t) -> Bool {
    let vendor = searchParents(service, "idVendor") as? Int
    let product = searchParents(service, "idProduct") as? Int
    return vendor == vendorID && product == productID
  }

  private static func property(_ service: io_object_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }

  private static func searchParents(_ service: io_object_t, _ key: String) -> Any? {
    let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
    return IORegistryEntrySearchCFProperty(
      service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
  }
}

@MainActor
public final class PortWatcher {
  private let notificationPort: IONotificationPortRef
  private var iterators: [io_iterator_t] = []
  private let onChange: @MainActor () -> Void

  public init(onChange: @escaping @MainActor () -> Void) {
    notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    self.onChange = onChange
    let source = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    watch(kIOFirstMatchNotification)
    watch(kIOTerminatedNotification)
  }

  private func watch(_ notification: String) {
    var iterator: io_iterator_t = 0
    let context = Unmanaged.passUnretained(self).toOpaque()
    let result = IOServiceAddMatchingNotification(
      notificationPort, notification, IOServiceMatching(PortLocator.serialClass),
      { context, iterator in
        PortWatcher.discard(iterator)
        guard let context else { return }
        MainActor.assumeIsolated {
          Unmanaged<PortWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
        }
      }, context, &iterator)
    guard result == KERN_SUCCESS else { return }
    PortWatcher.discard(iterator)
    iterators.append(iterator)
  }

  private nonisolated static func discard(_ iterator: io_iterator_t) {
    var service = IOIteratorNext(iterator)
    while service != 0 {
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }
  }
}
