import Cocoa
import Security
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
      } else if call.method == "openProject" {
        result(NSWorkspace.shared.open(URL(string: "https://github.com/sinri/TerminalUseApp")!))
      } else if call.method == "closeWindow" {
        result(nil)
        DispatchQueue.main.async { NSApp.terminate(nil) }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let credentials = FlutterMethodChannel(
      name: "terminal_use/ssh_credentials",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    credentials.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: String], let account = args["account"] else {
        result(FlutterError(code: "arguments", message: "缺少 SSH 账户", details: nil)); return
      }
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.terminal-use.ssh",
        kSecAttrAccount as String: account,
      ]
      var status: OSStatus
      if call.method == "read" {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { result(""); return }
        if status == errSecSuccess {
          result((item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""); return
        }
      } else if call.method == "save", let password = args["password"] {
        if password.isEmpty {
          status = SecItemDelete(query as CFDictionary)
          if status == errSecItemNotFound { status = errSecSuccess }
        } else {
          let data = Data(password.utf8)
          status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
          if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            status = SecItemAdd(entry as CFDictionary, nil)
          }
        }
        if status == errSecSuccess { result(nil); return }
      } else { result(FlutterMethodNotImplemented); return }
      result(FlutterError(code: "keychain", message: "系统钥匙串操作失败 (\(status))", details: nil))
    }
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    self.title = "Terminal Use APP"
  }
}
