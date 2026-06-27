# Windows OTA Manifest Contract

Windows OTA manifest 字段由两端共同维护：

- Dart runtime model: `desktop/lib/models/manifest_model.dart`
- Python publish model: `android/tools/publish/manifest.py`

修改任一端时必须同步另一端，并保持旧 manifest 可解析。

`ota.windows` 当前字段：

- `version`: Windows 平台版本号。
- `force_ota`: 是否强制更新。
- `url`: 安装器下载地址，作为兜底更新路径。
- `md5`: 旧客户端兼容字段，仅用于下载损坏检测。
- `sha256`: 安装器 SHA256。
- `type`: `native` 或 `web`。
- `package`: Windows 内部替换包，可缺省。

`ota.windows.package` 字段：

- `url`: 完整 zip 更新包下载地址。
- `sha256`: zip 更新包 SHA256。
- `enabled`: 远程 kill-switch，默认必须为 `false`。未显式开启时客户端降级到安装器。
