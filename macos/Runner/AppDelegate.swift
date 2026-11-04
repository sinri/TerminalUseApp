import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var lifecycleChannel: FlutterMethodChannel?
  private var terminating = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminating { return .terminateNow }
    guard let channel = AppDelegate.lifecycleChannel else { return .terminateNow }
    terminating = true
    channel.invokeMethod("shutdown", arguments: nil) { _ in
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
