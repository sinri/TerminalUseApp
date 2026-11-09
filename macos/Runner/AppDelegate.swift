import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var lifecycleChannel: FlutterMethodChannel?
  private var terminating = false
  private var terminationReplySent = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    installWorkspaceMenus()
  }

  @discardableResult
  func installWorkspaceMenus() -> Bool {
    guard let menu = NSApp.mainMenu else { return false }
    let menuID = NSUserInterfaceItemIdentifier("terminal-use-workspace")
    if menu.items.contains(where: { $0.identifier == menuID }) { return true }
    if let preferences = menu.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }) {
      preferences.title = "设置…"
      preferences.target = self
      preferences.action = #selector(openSettings(_:))
    }
    menu.items.first?.title = "Terminal Use APP"
    if let about = menu.items.first?.submenu?.items.first(where: {
      $0.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:))
    }) {
      about.title = "关于 Terminal Use APP"
      about.target = self
      about.action = #selector(openAbout(_:))
    }
    if let editMenu = menu.items.first(where: { $0.submenu?.items.contains(where: { $0.action == NSSelectorFromString("paste:") }) == true })?.submenu {
      let editActions: [String: Selector] = ["copy:": #selector(copyText(_:)), "paste:": #selector(pasteText(_:)), "selectAll:": #selector(selectAllText(_:))]
      for item in editMenu.items {
        if let original = item.action, let replacement = editActions[NSStringFromSelector(original)] {
          item.target = self
          item.action = replacement
        }
      }
    }
    let terminal = NSMenu(title: "终端")
    let actions: [(String, Selector, String, NSEvent.ModifierFlags)] = [
      ("新建终端", #selector(newTerminal(_:)), "t", [.command]),
      ("关闭标签页", #selector(closeTab(_:)), "w", [.command]),
      ("上一个终端", #selector(previousTab(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option]),
      ("下一个终端", #selector(nextTab(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option]),
      ("聚焦 Agent", #selector(focusAgent(_:)), "a", [.command, .shift]),
    ]
    for (title, action, key, modifiers) in actions {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = self
      terminal.addItem(item)
    }
    let entry = NSMenuItem(title: "终端", action: nil, keyEquivalent: "")
    entry.identifier = menuID
    entry.submenu = terminal
    menu.insertItem(entry, at: 1)
    return true
  }

  private func workspaceAction(_ action: String) {
    guard !terminating else { return }
    AppDelegate.lifecycleChannel?.invokeMethod(action, arguments: nil)
  }
  private func editAction(_ action: String, fallback: String, sender: Any?) {
    guard !terminating, let channel = AppDelegate.lifecycleChannel else { return }
    channel.invokeMethod("edit:" + action, arguments: nil) { handled in
      if (handled as? Bool) != true {
        DispatchQueue.main.async {
          NSApp.sendAction(NSSelectorFromString(fallback), to: nil, from: sender)
        }
      }
    }
  }
  @objc private func copyText(_ sender: Any?) { editAction("copy", fallback: "copy:", sender: sender) }
  @objc private func pasteText(_ sender: Any?) { editAction("paste", fallback: "paste:", sender: sender) }
  @objc private func selectAllText(_ sender: Any?) { editAction("selectAll", fallback: "selectAll:", sender: sender) }

  @objc private func openSettings(_ sender: Any?) { workspaceAction("settings") }
  @objc private func openAbout(_ sender: Any?) { workspaceAction("about") }
  @objc private func newTerminal(_ sender: Any?) { workspaceAction("newTerminal") }
  @objc private func closeTab(_ sender: Any?) { workspaceAction("closeTab") }
  @objc private func previousTab(_ sender: Any?) { workspaceAction("previousTab") }
  @objc private func nextTab(_ sender: Any?) { workspaceAction("nextTab") }
  @objc private func focusAgent(_ sender: Any?) { workspaceAction("focusAgent") }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminating { return .terminateLater }
    guard let channel = AppDelegate.lifecycleChannel else { return .terminateNow }
    terminating = true
    let started = Date()
    let finish: (String) -> Void = { [weak self] reason in
      guard let self = self, !self.terminationReplySent else { return }
      self.terminationReplySent = true
      NSLog("[shutdown] %@ after %.0f ms", reason, Date().timeIntervalSince(started) * 1000)
      sender.reply(toApplicationShouldTerminate: true)
    }
    // A paused/debug-disconnected Dart isolate must not hold app exit forever.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      finish("cleanup timeout")
    }
    channel.invokeMethod("shutdown", arguments: nil) { _ in
      DispatchQueue.main.async { finish("cleanup replied") }
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
