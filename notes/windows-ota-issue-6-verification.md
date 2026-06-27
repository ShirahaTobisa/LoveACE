# Windows OTA Issue #6 Verification Notes

本记录只描述自动验证状态，不替代 `WINDOWS_OTA_ISSUE_6_SPEC.md`。

## 已执行

- `cd desktop && flutter analyze --no-pub`
  - Flutter SDK: `D:\tools\codex\tools\flutter\bin\flutter.bat`
  - 结果：通过，`No issues found!`。
- `cd desktop && flutter test --no-pub`
  - 结果：通过，14 个测试全绿。
  - 覆盖：SHA256 正确/损坏、版本比较、UpdateStrategy 组合、journal 状态机、新旧 manifest 解析、非 Windows 平台节点回归。
- `cd desktop/windows/updater && dart test`
  - Dart SDK: `D:\tools\codex\tools\flutter\bin\dart.bat`
  - 结果：通过，4 个 helper 逻辑测试全绿。
- `cd desktop/windows/updater && dart compile exe bin/loveace_updater.dart -o build/loveace_updater.exe`
  - 结果：通过，成功产出 `loveace_updater.exe`。
- `cd android/tools/publish && python -B test_manifest_contract.py`
  - 结果：通过。
- Python 语法编译（通过 `compile(...)`，不写 `__pycache__`）
  - `android/tools/publish/manifest.py`
  - `android/tools/publish/cli.py`
  - `android/tools/publish/test_manifest_contract.py`
  - 结果：通过。
- `git diff --check`
  - 结果：通过，仅有 CRLF 提示。

## 环境说明

- 本机未全局安装 Flutter/Dart；已按要求把 Flutter 拉取到 `D:\tools\codex\tools\flutter`，验证命令使用完整路径执行。
- 本机 Windows Developer Mode / symlink 支持未启用，`flutter pub get` 会在插件 symlink 阶段失败；由于依赖解析文件已生成，自动验证使用 `--no-pub` 完成。
- Flutter SDK 下载源使用 `https://storage.flutter-io.cn`，Pub 下载源使用 `https://pub.flutter-io.cn`。提交前已恢复 `desktop/pubspec.lock` 的镜像源噪音；helper 新 lockfile 已改回 `https://pub.dev`。

## 人工验证

- TODO: 人工验证 - UAC 自提权与安装器实际覆盖。
- TODO: 人工验证 - 杀软对 helper 替换流程的反应。
- TODO: 人工验证 - 真机「关应用 -> 替换 -> 重启」端到端。
- TODO: 人工验证 - SmartScreen 表现；未签名产物不承诺消除 SmartScreen。
