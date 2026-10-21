import Testing

@testable import DasungKit

struct MonitorStateTests {
  @Test func appliesReportsToMatchingSettings() {
    var state = MonitorState()
    for (register, value) in [(0x01, 4), (0x02, 7), (0x07, 2), (0x08, 0), (0x09, 20)] {
      state.apply(.report(register: UInt8(register), value: UInt8(value)))
    }
    #expect(state.contrast == 4)
    #expect(state.displayMode == 7)
    #expect(state.frontLight == .warm)
    #expect(state.temperature == 0)
    #expect(state.brightness == 20)
  }

  @Test func ignoresAcknowledgementsAndUnknownRegisters() {
    var state = MonitorState()
    state.apply(.acknowledged(0x01))
    state.apply(.report(register: 0x0B, value: 1))
    state.apply(.report(register: 0x07, value: 9))
    #expect(state == MonitorState())
  }

  @Test(arguments: [(0x30, true), (0x31, true), (0x10, false), (0x32, false)])
  func frontLightDependsOnControllerVersion(version: Int, expected: Bool) {
    var state = MonitorState()
    state.apply(.report(register: 0x10, value: UInt8(version)))
    #expect(state.hasFrontLight == expected)
  }

  @Test func frontLightUnavailableBeforeVersionIsKnown() {
    #expect(MonitorState().hasFrontLight == false)
  }

  @Test func paperlike133kModesMatchVendorValues() {
    var state = MonitorState()
    state.apply(.report(register: 0x13, value: 1))
    #expect(state.modes.map(\.name) == ["M1 Web", "M2 Text", "M3 Image", "M4 Active"])
    #expect(state.modes.map(\.value) == [6, 2, 3, 7])
  }

  @Test func unknownModelHasNoModes() {
    var state = MonitorState()
    state.apply(.report(register: 0x13, value: 9))
    #expect(state.modes.isEmpty)
    #expect(state.mode(after: 2) == nil)
  }

  @Test(arguments: [(nil, 6), (6, 2), (3, 7), (7, 6), (99, 6)] as [(UInt8?, UInt8)])
  func cyclesThroughModesAndWraps(current: UInt8?, expected: UInt8) {
    var state = MonitorState()
    state.apply(.report(register: 0x13, value: 1))
    #expect(state.mode(after: current)?.value == expected)
  }
}
