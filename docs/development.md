# 开发与构建

[文档导航](README.md) · [架构](architecture.md) · [诊断](debugging.md) · [签名发行](releasing.md)

本文面向从源码运行、修改和测试项目的开发者。安装发行包请看根目录 [README](../README.md)。
已验证工具链为 Flutter 3.47.9；`pubspec.lock` 固定 Dart 依赖，`macos/Podfile.lock` 固定原生依赖。

## 环境与常用命令

需要 Flutter、对应桌面平台构建工具；macOS 最低 12.0，另需 Xcode 和 CocoaPods。

```sh
flutter pub get
flutter run -d macos
# Linux / Windows 分别使用 -d linux / -d windows
```

```sh
flutter build macos --release
flutter analyze
flutter test
# 真实桌面 UI + Python MCP → HTTP → PTY 集成测试（需要 Python 3）
flutter test integration_test/terminal_test.dart -d macos
```

Release / Profile 默认按构建机器的本机架构生成（Apple Silicon 为 arm64，Intel 为 x86_64），配置位于 `macos/Runner/Configs/Release.xcconfig`。这是为了规避本机 Xcode `lipo -verify_arch arm64 x86_64` 的参数兼容问题；标准 `flutter build macos --release` 和 IDE 的 Release 运行均可直接使用。当前默认产物不是通用双架构包；跨架构分发需在解决工具链问题后另行构建验证。

产物位于 `build/macos/Build/Products/Release/terminal_use_app.app`。

本机 Flutter 3.41.5 的 `flutter run --release` 在 App 退出后可能继续等待，导致 IDE 的运行状态未结束。推荐在 IDE Terminal 或 Shell Script 运行配置中使用：

```sh
./tools/run_macos_release.sh
# 如果 Flutter 不在 PATH 中：
FLUTTER_BIN=/path/to/flutter/bin/flutter ./tools/run_macos_release.sh
```

脚本先生成 Flutter Release 配置，使用明确的本机 Xcode destination 构建，再以 `exec` 运行 App。关窗后命令随 App 进程退出，且不会触发 Any Mac 占位目标的版本 warning。此方式不使用 Flutter IDE 调试协议；调试仍用普通 Debug 运行配置。

Flutter 3.47.9 使用默认的合并 UI / 平台线程，已移除针对 Flutter 3.41 的 `FLTEnableMergedPlatformUIThread=false` 旧兼容开关；新 SDK 已弃用分离线程。IDE 的 `--machine --start-paused` 会在入口暂停，需调试器继续运行后才绘制 Dart 首屏。

`flutter_pty` 暂时保持 pub.dev 0.4.2 与 CocoaPods 构建，项目 `pubspec.yaml` 禁用 SPM 集成，避免未完成迁移影响终端动态库加载。Flutter 3.47.9 仍可能输出插件缺少 SPM 支持的警告；迁移验证完成前保留此提示。原生依赖切换后需停止应用并重新编译，热重载不足以更新动态库。

## 平台与依赖限制

当前在 macOS 开发验证，Linux/Windows 已生成平台工程，但尚未在对应系统验证。原生签名、公证和发行使用 [发行指南](releasing.md) 中的流水线；上面的 Release 构建仅用于本机运行。

## 修改后的验证

修改 Dart 逻辑时运行 `flutter analyze` 和相关单元测试；平台桥接、PTY 或桌面输入改动还需在 macOS 实际构建和运行集成测试。Linux/Windows 原生变更需在相应系统验证。

发版工具的测试独立运行：

```sh
python3 -m unittest discover -s tools/release -p 'test_*.py'
```

当前已完成的验证见 [实施状态](implementation-plan.md)，不要将历史验证记录当作新变更的测试结果。

## 代码与资产入口

模块职责见 [架构与数据流](architecture.md)。界面遵循 [桌面界面规范](ui-design.md)。
图标源文件与再生成命令见 [图标维护说明](../tools/icons/README.md)，字体及第三方依赖见 [许可证清单](dependency-licenses.md)。

## 文档维护

用户可见行为更新 [使用指南](user-guide.md)；协议更新 [MCP 接入](mcp.md) 和 [HTTP API](http-api.md)；构建或依赖变更更新本文及许可证清单；发行操作更新 [发行指南](releasing.md) 与根目录 [更新记录](../CHANGELOG.md)。
根目录 README 只保留产品介绍、安装、快速上手、权限和用户入口，不放工具链排障或协议实现细节。
