import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 1200, height: 780), display: true)
    self.minSize = NSSize(width: 720, height: 640)
    self.title = "Terminal Use"

    AppDelegate.lifecycleChannel = FlutterMethodChannel(
      name: "terminal_use/lifecycle",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
