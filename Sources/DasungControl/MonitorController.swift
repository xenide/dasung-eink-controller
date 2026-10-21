import AppKit
import DasungKit
import Observation
import ServiceManagement

@MainActor
@Observable
final class MonitorController {
  enum Status: Equatable {
    case searching
    case connecting
    case connected
    case unresponsive
    case failed(String)
  }

  private static let handshake: [Register] = [
    .modelVersion, .controllerVersion, .contrast, .displayMode, .frontLight, .brightness,
    .temperature,
  ]
  private static let ditheringKey = "disableDithering"

  private(set) var status: Status = .searching
  private(set) var state = MonitorState()
  private(set) var ditheringError: String?
  private(set) var loginItemError: String?
  private(set) var shortcutFailures: [Shortcut] = []
  private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

  var ditheringDisabled: Bool {
    didSet {
      UserDefaults.standard.set(ditheringDisabled, forKey: Self.ditheringKey)
      applyDithering()
    }
  }

  @ObservationIgnored private var connection: SerialConnection?
  @ObservationIgnored private var connectionID = UUID()
  @ObservationIgnored private var watcher: PortWatcher?
  @ObservationIgnored private let hotKeys = HotKeys()
  @ObservationIgnored private var pending: [Register: UInt8] = [:]
  @ObservationIgnored private var flushTask: Task<Void, Never>?
  @ObservationIgnored private var handshakeTimeout: Task<Void, Never>?
  @ObservationIgnored private var observers: [any NSObjectProtocol] = []

  init() {
    UserDefaults.standard.register(defaults: [Self.ditheringKey: true])
    ditheringDisabled = UserDefaults.standard.bool(forKey: Self.ditheringKey)
  }

  func start() {
    watcher = PortWatcher { [weak self] in self?.connectIfNeeded() }
    registerShortcuts()
    observeDisplayChanges()
    if ditheringDisabled { applyDithering() }
    connectIfNeeded()
  }

  func retry() {
    connection?.close()
    connection = nil
    status = .searching
    connectIfNeeded()
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginItemError = nil
    } catch {
      loginItemError = "Couldn't update login item: \(error.localizedDescription)"
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func refresh() {
    connection?.send(.refresh, value: 0)
  }

  func select(mode value: UInt8) {
    state.displayMode = value
    connection?.send(.displayMode, value: value)
  }

  func nextMode() {
    guard let mode = state.mode(after: state.displayMode) else { return }
    select(mode: mode.value)
  }

  func setContrast(_ level: Int) {
    let clamped = level.clamped(to: MonitorState.contrastRange)
    state.contrast = clamped
    connection?.send(.contrast, value: UInt8(clamped))
  }

  func adjustContrast(by delta: Int) {
    guard let contrast = state.contrast else { return }
    setContrast(contrast + delta)
  }

  func setFrontLight(_ light: FrontLight) {
    state.frontLight = light
    connection?.send(.frontLight, value: light.rawValue)
  }

  func setBrightness(_ level: Int) {
    let clamped = level.clamped(to: MonitorState.lightRange)
    state.brightness = clamped
    schedule(.brightness, UInt8(clamped))
  }

  func adjustBrightness(by delta: Int) {
    guard state.hasFrontLight, let brightness = state.brightness else { return }
    setBrightness(brightness + delta)
  }

  func setTemperature(_ level: Int) {
    let clamped = level.clamped(to: MonitorState.lightRange)
    state.temperature = clamped
    schedule(.temperature, UInt8(clamped))
  }

  private func connectIfNeeded() {
    guard connection == nil else { return }
    guard let path = PortLocator.candidatePaths().first else {
      status = .searching
      return
    }
    let id = UUID()
    do {
      connection = try SerialConnection(
        path: path,
        onReply: { [weak self] reply in Task { @MainActor in self?.receive(reply) } },
        onClose: { [weak self] in Task { @MainActor in self?.connectionClosed(id: id) } })
      connectionID = id
      status = .connecting
      startHandshake()
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func startHandshake() {
    for register in Self.handshake { connection?.query(register) }
    handshakeTimeout?.cancel()
    handshakeTimeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      guard let self, self.status == .connecting else { return }
      self.status = .unresponsive
    }
  }

  private func receive(_ reply: Reply) {
    state.apply(reply)
    if case .report = reply, status != .connected {
      status = .connected
      handshakeTimeout?.cancel()
    }
  }

  private func connectionClosed(id: UUID) {
    guard connectionID == id else { return }
    connection = nil
    state = MonitorState()
    status = .searching
    connectIfNeeded()
  }

  private func schedule(_ register: Register, _ value: UInt8) {
    pending[register] = value
    guard flushTask == nil else { return }
    flushTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
      self?.flushPending()
    }
  }

  private func flushPending() {
    for (register, value) in pending { connection?.send(register, value: value) }
    pending = [:]
    flushTask = nil
  }

  private func applyDithering() {
    do {
      try Dithering.set(enabled: !ditheringDisabled)
      ditheringError = nil
    } catch {
      ditheringError = error.localizedDescription
    }
  }

  private func observeDisplayChanges() {
    let reapply: @Sendable (Notification) -> Void = { [weak self] _ in
      Task { @MainActor in
        guard let self, self.ditheringDisabled else { return }
        self.applyDithering()
      }
    }
    observers = [
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main,
        using: reapply),
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reapply),
    ]
  }

  private func registerShortcuts() {
    hotKeys.register([
      .refresh: { [weak self] in self?.refresh() },
      .nextMode: { [weak self] in self?.nextMode() },
      .contrastUp: { [weak self] in self?.adjustContrast(by: 1) },
      .contrastDown: { [weak self] in self?.adjustContrast(by: -1) },
      .lightUp: { [weak self] in self?.adjustBrightness(by: 10) },
      .lightDown: { [weak self] in self?.adjustBrightness(by: -10) },
    ])
    shortcutFailures = hotKeys.failures
  }
}

extension Int {
  fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
