import SwiftUI

@main
struct DasungControlApp: App {
  @State private var controller: MonitorController

  init() {
    let controller = MonitorController()
    controller.start()
    _controller = State(initialValue: controller)
  }

  var body: some Scene {
    MenuBarExtra {
      ControlPanel(controller: controller)
    } label: {
      Image(systemName: controller.status == .connected ? "book.pages.fill" : "book.pages")
    }
    .menuBarExtraStyle(.window)
  }
}
