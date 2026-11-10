# 本地依赖修复

保留上游源代码和各包 LICENSE。通过 pubspec.yaml 的 dependency_overrides 使用。

- flutter_pty 0.4.2，修复 Windows argv 重复及引用、UTF-8 启动目录和环境变量转换，并移除阻塞输入线程的 FlushFileBuffers。
- xterm 4.0.0，为 TextInputConfiguration 提供当前 Flutter View 的 viewId，兼容 Flutter 3.47.9。
