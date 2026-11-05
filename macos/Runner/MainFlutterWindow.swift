import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Keep the Flutter engine alive while Dart closes terminals and the bridge.
  override func performClose(_ sender: Any?) {
    NSApp.terminate(sender)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 1200, height: 780), display: true)
    self.minSize = NSSize(width: 720, height: 640)

    AppDelegate.lifecycleChannel = FlutterMethodChannel(
      name: "terminal_use/lifecycle",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    AppDelegate.lifecycleChannel?.setMethodCallHandler { call, result in
      if call.method == "installMenus" {
        result((NSApp.delegate as? AppDelegate)?.installWorkspaceMenus() ?? false)
      } else if call.method == "closeWindow" {
        result(nil)
        DispatchQueue.main.async { NSApp.terminate(nil) }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    self.title = "Terminal Use"
  }
}
