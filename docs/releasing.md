# macOS 发行流程

发行渠道为 GitHub Release，提供 Developer ID 签名、Apple 公证并 stapler 的 DMG。
脚本：`python3 tools/release/release.py --help`。凭据只保存在本机钥匙串，不提交证书或密码。

## 一次性准备

1. 安装 Xcode（完成首次启动）、CocoaPods、Python 3.9+、GitHub CLI；使用项目已验证的 Flutter 3.47.9。
2. 在 Apple Developer / Xcode 中创建 **Developer ID Application** 证书，安装到登录钥匙串。必须有对应私钥；Apple Development、Apple Distribution 和 Developer ID Installer 不能替代它。
3. `security find-identity -v -p codesigning` 确认证书可用。
4. 在终端设置以下环境变量（替换成自己的值）：

   ```sh
   export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
   export NOTARY_PROFILE='terminal-use-notary'
   ```

5. 交互式保存公证凭据；在提示中填写 Apple ID、Team ID 和 Apple ID 的 App 专用密码，避免将密码写入命令历史：

   ```sh
   xcrun notarytool store-credentials "$NOTARY_PROFILE"
   gh auth login
   python3 tools/release/release.py doctor
   ```

账号需要具备证书及公证权限，并已接受 Apple 协议。Developer ID + hardened runtime 是站外公证要求。
`doctor` 会访问 Apple 验证钥匙串配置，并检查 GitHub 登录状态。证书可能首次触发钥匙串授权提示。

## 版本规则

唯一来源是 `pubspec.yaml` 的 `version: MAJOR.MINOR.PATCH+BUILD`。
每次递增都让 BUILD 加 1；major/minor 会重置其下级版本。`build` 用于相同语义版本的重新发行。
Git 标签包含完整版本，例如 `v1.0.1+2`，避免同版本重新打包的歧义。脚本不会自动提交或打标签。

```sh
python3 tools/release/release.py version
python3 tools/release/release.py bump patch  # 也支持 major / minor / build
# 编辑 CHANGELOG.md，记录此版本改动
flutter analyze
flutter test
python3 -m unittest discover -s tools/release -p 'test_*.py'
git add pubspec.yaml CHANGELOG.md
git commit -m 'Release 1.0.1+2'
git tag -a v1.0.1+2 -m 'Terminal Use APP 1.0.1+2'
python3 tools/release/release.py build
```

首次发行可以直接使用现有 `1.0.0+1`，提交发行机制后打 `v1.0.0+1` 标签，无须为了发行而强制递增。

## 打包做什么

- 要求工作区干净、完整版本标签指向 HEAD；严格按锁文件取依赖，运行 analyze 和全部 Flutter 单元测试。
- 在本机架构构建 Release，启用 hardened runtime。分发标识为 `io.github.sinri.TerminalUseApp`。
- 校验包内版本和架构，逐个签名所有 Mach-O（包括 PTY 动态库）、framework 和主 App，并验证嵌套签名。
- 公证 App、装订票据并做 Gatekeeper 检查；再生成含 Applications 快捷方式的 DMG，对 DMG 签名、公证、装订并检查。
- 输出对应标签的源码压缩包（不含依赖）、构建清单及 SHA-256；App 内含 GPL 全文和 Flutter 自动生成的依赖许可证。
- 只有全部成功后才生成 `release.json`，允许后续上传；失败保留公证记录供诊断。重试时先移走失败的架构输出目录，不会覆盖已有候选包。

输出在 `dist/v版本+构建号/arm64/` 或 `x86_64/`，不进入 Git。
当前只发行构建机器对应架构，文件名明确标识；Apple Silicon 包不能宣称支持 Intel。
要支持 Intel，请在实际 Intel Mac 上用同一标签构建并测试；当前上传命令一次创建一个架构的草稿，另一架构验收后可用 `gh release upload` 补充，不能覆盖现有资产。

项目当前曾遇到本机通用架构构建问题，因此不默认生成 universal 包。
macOS 最低版本当前配置为 12.0；升级 Flutter 后需要重新确认最低系统要求。

## 安装验收与发布

对最终 DMG（从 GitHub 草稿下载的同一文件）在独立用户或另一台匹配架构的 Mac 上验收：

1. 打开 DMG，将 App 拖入 Applications，直接双击启动，无需绕过 Gatekeeper。
2. 检查菜单和 About、GPL 和第三方许可，创建终端，执行命令，验证中文输入、退出和重新启动。
3. 验证 SSH 密钥/密码钥匙串读取、设置保存，以及 Agent 网络请求和终端操作。
4. 如使用 Python MCP，确认用户已安装 Python 3。SSH、用户 shell、Python、模型服务均不是此包内置依赖。
5. 在声明支持的 macOS/CPU 上完成测试；编译、公证通过不等同于功能验收。

上传为草稿（会推送当前标签，**不会公开发布**）：

```sh
python3 tools/release/release.py publish 'dist/v1.0.1+2/arm64'
```

脚本检查标签/提交及产物校验和，然后生成带自动 release notes 的 GitHub 草稿。人工整理说明，写明系统要求、CPU 架构、已知限制、源码及安装方式。完成安装验收后在 GitHub 点击 Publish release。
首次发布前确认仓库是公开开源仓库；脚本不更改仓库可见性。

## 失败与撤回

公证返回 Invalid 时，用记录中的 submission id 查询：

```sh
xcrun notarytool log SUBMISSION_ID --keychain-profile "$NOTARY_PROFILE"
```

凭据/证书缺失时脚本立即停止，不生成可上传收据。不要取消签名或跳过公证来发布。
发行后发现问题应撤回问题 release，递增 BUILD 或 PATCH 并创建新标签；不要移动已经公开发行的标签。
更新签名证书时保持 bundle identifier 不变。现有开发版的 `com.example.terminalUseApp` 已改为稳定发行标识，首次迁移可能需要重新授权钥匙串访问。

官方参考：[Developer ID](https://developer.apple.com/developer-id/)、[公证流程](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[Flutter macOS 发行](https://docs.flutter.dev/deployment/macos)。
