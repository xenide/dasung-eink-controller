import DasungKit
import SwiftUI

struct ControlPanel: View {
  let controller: MonitorController

  private var state: MonitorState { controller.state }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      if controller.status == .connected {
        refreshButton
        displaySection
        if state.hasFrontLight { lightSection }
      } else {
        StatusMessage(status: controller.status, retry: controller.retry)
      }
      Divider()
      preferences
      Divider()
      footer
    }
    .padding(16)
    .frame(width: 340)
  }

  private var header: some View {
    HStack {
      Label("Paperlike", systemImage: "rectangle.inset.filled")
        .font(.headline)
      Spacer()
      StatusBadge(status: controller.status)
    }
  }

  private var refreshButton: some View {
    Button(action: controller.refresh) {
      HStack {
        Label("Refresh screen", systemImage: "arrow.clockwise")
        Spacer()
        Text(Shortcut.modifierSymbols + Shortcut.refresh.key).opacity(0.7)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .keyboardShortcut(.defaultAction)
  }

  private var displaySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !state.modes.isEmpty {
        Setting("Display mode") {
          Picker("Display mode", selection: modeBinding) {
            ForEach(state.modes) { Text($0.name).tag($0.value) }
          }
        }
      }
      Setting("Contrast") {
        Picker("Contrast", selection: contrastBinding) {
          ForEach(MonitorState.contrastRange, id: \.self) { Text("\($0)").tag($0) }
        }
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }

  private var lightSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Setting("Front light") {
        Picker("Front light", selection: frontLightBinding) {
          ForEach(FrontLight.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      if state.frontLight != .off {
        LevelSlider(
          title: "Brightness", value: state.brightness, minimum: "sun.min", maximum: "sun.max",
          onChange: controller.setBrightness)
      }
      if state.frontLight == .mixed {
        LevelSlider(
          title: "Color temperature", value: state.temperature, minimum: "flame",
          maximum: "snowflake", onChange: controller.setTemperature)
      }
    }
  }

  private var preferences: some View {
    VStack(alignment: .leading, spacing: 8) {
      SwitchRow("Disable display dithering", isOn: ditheringBinding)
      ErrorText(controller.ditheringError)
      SwitchRow("Launch at login", isOn: launchBinding)
      ErrorText(controller.loginItemError)
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      DisclosureGroup("Keyboard shortcuts") {
        ShortcutList(failures: controller.shortcutFailures)
      }
      .font(.callout)
      HStack {
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
          .keyboardShortcut("q")
      }
    }
  }

  private var modeBinding: Binding<UInt8> {
    Binding(get: { state.displayMode ?? 0 }, set: { controller.select(mode: $0) })
  }

  private var contrastBinding: Binding<Int> {
    Binding(get: { state.contrast ?? 0 }, set: { controller.setContrast($0) })
  }

  private var frontLightBinding: Binding<FrontLight> {
    Binding(get: { state.frontLight ?? .off }, set: { controller.setFrontLight($0) })
  }

  private var ditheringBinding: Binding<Bool> {
    Binding(get: { controller.ditheringDisabled }, set: { controller.ditheringDisabled = $0 })
  }

  private var launchBinding: Binding<Bool> {
    Binding(get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) })
  }
}

private struct Setting<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
      content
    }
  }
}

private struct SwitchRow: View {
  let title: String
  @Binding var isOn: Bool

  init(_ title: String, isOn: Binding<Bool>) {
    self.title = title
    _isOn = isOn
  }

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Toggle(title, isOn: $isOn)
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
    }
  }
}

private struct LevelSlider: View {
  let title: String
  let value: Int?
  let minimum: String
  let maximum: String
  let onChange: (Int) -> Void

  var body: some View {
    Setting(title) {
      HStack(spacing: 8) {
        Image(systemName: minimum).foregroundStyle(.secondary).frame(width: 18)
        Slider(value: binding, in: 0...100)
          .accessibilityLabel(title)
        Image(systemName: maximum).foregroundStyle(.secondary).frame(width: 18)
        Text(value.map(String.init) ?? "–")
          .monospacedDigit()
          .frame(width: 28, alignment: .trailing)
      }
    }
  }

  private var binding: Binding<Double> {
    Binding(get: { Double(value ?? 0) }, set: { onChange(Int($0.rounded())) })
  }
}

private struct StatusBadge: View {
  let status: MonitorController.Status

  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(text).font(.caption).foregroundStyle(.secondary)
    }
  }

  private var text: String {
    switch status {
    case .connected: "Connected"
    case .connecting: "Connecting…"
    case .searching: "Not found"
    case .unresponsive: "No response"
    case .failed: "Error"
    }
  }

  private var color: Color {
    switch status {
    case .connected: .green
    case .connecting: .yellow
    case .searching: .gray
    case .unresponsive, .failed: .red
    }
  }
}

private struct StatusMessage: View {
  let status: MonitorController.Status
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(message).font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if status != .connecting {
        Button("Try again", action: retry)
      }
    }
  }

  private var message: String {
    switch status {
    case .connected, .connecting: "Talking to the monitor…"
    case .searching: "Connect the monitor's USB cable to this Mac."
    case .unresponsive: "Found a USB serial port, but the monitor didn't answer."
    case .failed(let reason): reason
    }
  }
}

private struct ShortcutList: View {
  let failures: [Shortcut]

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
      ForEach(Shortcut.allCases, id: \.self) { shortcut in
        GridRow {
          Text(Shortcut.modifierSymbols + shortcut.key).monospaced()
          Text(failures.contains(shortcut) ? "\(shortcut.label) (in use)" : shortcut.label)
            .foregroundStyle(failures.contains(shortcut) ? .red : .secondary)
        }
      }
    }
    .font(.caption)
    .padding(.top, 4)
  }
}

private struct ErrorText: View {
  let message: String?

  init(_ message: String?) {
    self.message = message
  }

  var body: some View {
    if let message {
      Text(message).font(.caption).foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
