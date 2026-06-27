# LoveACE Windows Desktop 内部 OTA 完整实施方案（Issue #6）

> 本文件是可直接交付实施的单一方案，合并了可行性调查、实施方案与多人协作可维护性约束。
> 目标读者：实施者（人或 AI）。读这一份即可，无需其它 OTA 文档。
> 项目性质：多人开源。所有设计都以「普通贡献者零额外负担、坏版本可远程回收、平台代码隔离」为硬约束。

---

## ⚠️ 实施者必读（范围锁定，先看这一段）

> 🚫 **禁止自动提交 PR / 推送**：本次**严禁** `git push`、`gh pr create` 或以任何方式开/推 PR。
> 改动**只允许留在本地工作区**，最多做**本地 `git commit`**。全部完成后停下，等待人工审查；是否提交 PR 由人决定。
> （下文「一个 PR 交付」「按 Phase 分 commit」仅描述最终人工提交时的形态，**不授权你自动 push 或开 PR**。）

**交付目标：完整闭掉 Issue #6，一个 PR 交付 Phase 1 + 2 + 3 全部（见第 8 部分）。**

1. **全做，含 Phase 3（内部替换 + helper）**——这是 Issue #6「替换/重启流程」验收标准的核心，必须落地，不能省。
2. **Phase 3 默认用 kill-switch 关闭**（manifest `package.enabled=false`，见 §9 修正 D）。代码完整提交，但默认走安装器兜底路；因为本项目不采购代码签名（§7.1），未签名 helper 在部分杀软上可能误报，需后续灰度验证好了再把开关打开。**「默认关闭」是为了安全合并完整代码，不是"不做"。**
3. **硬红线：改动不得影响除 Windows 外的任何平台的运行时行为**（保证机制见 §2.1 路线甲 + 回归测试）。这是不可破的约束。
4. **不采购任何付费证书**，按无签名设计；UI 文案不要承诺消除 SmartScreen（§7.1）。
5. **方案 A（应用内下载安装器）已实现且在跑**（§2 实证），是在其上扩展，不是从零开发；复用现有 `WindowsUpdateService` 与 `WinUIOTADialog`。
6. `widgets/ota_update_dialog.dart` 是死代码，**不要动**；只改 winui 路径。
7. 单一 PR 内建议按 Phase 1→2→3 分 commit，便于回溯；高风险的 Phase 3 必须带单测（§9 修正 F）。

### 完成定义（Definition of Done）与自测要求 —— codex 必须逐条达成

**必须通过的自动检查（"做完"的硬标准）：**
1. 代码完成：Phase 1+2+3 全部按第 8 部分实现。
2. 静态检查：`cd desktop && flutter analyze` 零 error。
3. 单元测试：`cd desktop && flutter test` 全绿。新增测试**必须是不依赖 Windows 运行时的纯逻辑测试**，能在任何平台跑：
   - SHA256 校验（正确 + 损坏两例）；
   - 版本比较 `_isNewerVersion`（确保不回归）；
   - 更新决策函数 `UpdateStrategy`（可写×有包×kill-switch 各组合）；
   - update journal 状态机（pending→done / →failed 回滚）；
   - manifest 解析新字段 + **旧 manifest（无新字段）回归解析**（守 §2.1 红线）；
   - 断言非 Windows 平台节点解析不受影响。
4. 发布端：若改了 `manifest.py`/`cli.py`，跑其导入/测试校验，并补「旧 manifest 仍解析」测试。
5. helper：`dart compile exe` 能产出 `loveace_updater.exe`（需 Dart SDK 环境）；其纯逻辑（路径/journal 解析、目录改名计划）必须有 dart 单测覆盖。

**只能人工真机验证、codex 不得声称已验证（标注 `TODO: 人工验证`）：**
- UAC 自提权弹窗与安装器实际覆盖；
- 杀软对 helper「杀进程 + 换 exe」的反应；
- 真正的「关应用 → 替换 → 重启」端到端；
- SmartScreen 表现。

**环境降级规则**：codex 若自身环境无法跑 `flutter build windows`（如在 Linux），**不要硬试也不要因此判失败**；保证 `flutter analyze` + `flutter test` 通过即可，Windows 实际构建交给 CI / 人工。**严禁为了让测试"绿"而把 Windows 运行时逻辑 mock 成永远成功——那是自欺。** 宁可把这类留作 `TODO: 人工验证`。

---

## 第 0 部分　Issue #6 完成标准对照

| 完成标准 | 本文对应章节 |
| --- | --- |
| 调研 Windows desktop 内部 OTA 可行方案 | 第 2 部分（现状）、第 3 部分（架构） |
| 明确更新包格式 / 下载 / 校验 / 替换重启流程 | 第 5、6 部分 |
| 评估代码签名 / 权限 / 回滚 / 失败恢复 | 第 7 部分 |
| 给出实现方案 / 分阶段落地计划 | 第 8 部分 |

---

## 第 1 部分　目标与非目标

**目标**
- 减少用户手动去浏览器下载安装器的频率与被拦截概率。
- 安装目录可写时，做到「应用内直接替换文件 + 重启」的真正内部 OTA。
- 不可写 / 信息缺失时安全降级，绝不把用户卡死。
- 对普通贡献者透明：加功能 / 修 bug 不需要懂 OTA。

**非目标（明确排除，控制复杂度）**
- 增量 / delta 补丁。
- 常驻 updater 服务、后台静默自动更新。
- 强制迁移老的 Program Files 安装。
- 用 OTA 解决未签名导致的 SmartScreen（那是签名问题，见 §7.1）。

---

## 第 2 部分　现状基线（实证，含文件行号）

实施前请确认以下事实仍然成立：

| 能力 | 状态 | 位置 |
| --- | --- | --- |
| 应用内下载安装器 + MD5 校验 + 失败删文件 | ✅ 已实现 | `desktop/lib/services/windows_update_service.dart:43`（下载）、`:85-96`（校验） |
| 启动安装器 | ✅ 已实现 | `windows_update_service.dart:102-120`，`Process.start(detached)`，参数 `/SP- /NORESTART /CLOSEAPPLICATIONS` |
| 「下载并安装」/「复制链接」双态按钮 | ✅ 已实现 | `desktop/lib/winui/widgets/winui_ota_dialog.dart:119-144`；判定 `canInstallInApp` 在 `:43-45`（= `isWindows && type=='native' && md5 非空`） |
| manifest 拉取 | ✅ | `desktop/lib/services/manifest_service.dart` |
| 平台版本比较 / 是否有更新 | ✅ | `desktop/lib/providers/manifest_provider.dart:57`（hasOTAUpdate）、`:166`（_isNewerVersion） |
| manifest 数据模型（Dart） | ✅ | `desktop/lib/models/manifest_model.dart`：`PlatformRelease`(:53-77)、`OTA`(:83-129) |
| manifest 数据模型（Python，发布端） | ✅ | `android/tools/publish/manifest.py` |
| 安装器：Program Files + admin | ✅ | `desktop/windows/inno-ci.iss:21`（`DefaultDirName={autopf}\LoveACE`），Inno 默认 `PrivilegesRequired=admin` |
| 安装器文件清单用通配符 | ✅ | `inno-ci.iss:40-42`（`*.dll`、`data\*` 递归） |
| CI 构建+打包+发布 | ✅ | `.github/workflows/build-desktop-windows.yml`（flutter build → ISCC → artifact → upload-manifest 在 ubuntu 跑 `cli.py`） |
| MD5 计算 / 发布 | ✅ | `android/tools/publish/cli.py:35-41`（get_file_md5）、release 命令上传 S3 key `loveace/releases/{platform}/{version}/{filename}` |
| **内部文件替换 / 回滚 / 可写检测 / SHA256 / 代码签名** | ❌ 未实现 | 本方案新增 |

**基线结论**：已实现的是「应用内下载安装器」（即把跑安装器收进应用内）；真正的「内部替换」尚未实现。本方案在现有基础上**新增内部替换主路，并把安装器路降级为兜底，复用现有 service 与对话框，不重写**。

**「方案 A 已实现」已实证确认（真接线，非死代码）：**
- 启动触发链：`winui_main_shell.dart:93 _checkManifest()` → `:104-118` 判 `hasOTAUpdate`/`isForceUpdate` → `:140 WinUIOTADialog.show()`。
- 下载/启动链：`winui_ota_dialog.dart:392 WindowsUpdateService.downloadInstaller` + `:405 launchInstaller`。
- 依赖齐全可编译：`desktop/pubspec.yaml` 含 `crypto ^3.0.3 / dio ^5.9.2 / path_provider ^2.1.5 / path ^1.9.0`。
- `widgets/ota_update_dialog.dart` 的 Material 版 `OTAUpdateDialog` **全项目无任何调用，是死代码**。desktop 只用 winui 的 `WinUIOTADialog`，本方案只改这一个对话框。

### 2.1 涉及范围与红线（已定稿）

**涉及范围：Desktop Windows Release / CI。** 以下文件在范围内，可改：
- `desktop/lib/services/windows_update_service.dart`、`desktop/lib/winui/widgets/winui_ota_dialog.dart`（Windows app/UI）
- `desktop/windows/inno-ci.iss`（Windows 安装器）、`.github/workflows/build-desktop-windows.yml`（Windows CI）
- `android/tools/publish/cli.py` + `manifest.py`（发布管线 = Release 的一部分）
- 新建 helper 子工程

**红线（硬约束）：改动不得影响除 Windows 外的任何平台的运行时行为。**

**保证机制（采用「路线甲」+ 回归测试）：**
- manifest 新字段（`sha256`/`package`）只加在 JSON 的 `windows` 节点。其它平台读自己的节点（`manifest_model.dart:113-128 getPlatformRelease`），结构上不碰 windows 节点。
- 共享模型 `PlatformRelease` 加的是**可选字段 + 默认值**，沿用本文件现有的 `@JsonKey(defaultValue: ...)` 写法（见 `manifest_model.dart:54-63`）。其它平台读自己的节点拿到默认值，**行为零变化**。
- **回归测试兜底**：喂一份不含新字段的旧 manifest，断言非 Windows 平台解析结果与改动前一致。CI 跑，回归即红灯。
- Python 端首选在 `cli.py` 的 windows 发布路径把新字段作为 dict 写入 windows 节点；若 `manifest.py` 模型禁止额外字段（pydantic `extra='forbid'`）才加可选字段，并补同样的旧-manifest 解析测试。

---

## 第 3 部分　推荐架构：单一入口 + 三态自动决策

OTA 触发时由代码自动决策，用户只看到一个「立即更新」按钮：

```
读取 manifest → 进入更新决策（纯函数，见 §9 修正B）
│
├─ 内部替换允许(kill-switch on) + 安装目录可写 + 有 zip 包 + 有 sha256
│        → 【内部替换 OTA】（新建，主路，无 UAC）
│
├─ 不可写 / 无 zip 包 / 内部替换被远程关闭
│        → 【下载并启动安装器】（已实现，兜底，走 UAC）
│
└─ 非 native / 缺校验信息
         → 【复制链接】（已实现，最终降级）
```

设计原则：
- **能力探测而非用户配置**——用户不需要懂用户级/系统级。
- **降级链单向无死角**——任一态失败都能掉到下一态；漏配只降级不报错。
- **决策逻辑单点**——见 §9 修正 B。

---

## 第 4 部分　安装目录策略（内部替换的前置）

内部替换只在安装目录可写时成立。

- **新装用户**：`inno-ci.iss` 默认目录 `{autopf}\LoveACE` → `{localappdata}\Programs\LoveACE`，
  **并同时设 `PrivilegesRequired=lowest`**。
  ⚠️ 只改目录不改这行无效，Inno 仍会提权到 admin。
- **老的 Program Files 用户**：不迁移、不强制；其 OTA 自动走安装器兜底路，零破坏。
- **可写性检测**：运行期向 install dir 写一个临时探针文件，成功即判可写（比判断"是不是 Program Files"可靠，用户可能装在任意目录）。
- **双版本共存**：per-user 与遗留 per-machine 可能并存。首版只做检测+提示，不自动清理（避免快捷方式/卸载注册表残留问题）。

---

## 第 5 部分　更新包格式与 manifest 演进

### 5.1 更新包
- **内部替换包**：完整 zip，内容 = `desktop/build/windows/x64/runner/Release/` 全量（`loveace.exe` + 所有 `*.dll` + `data/` 整树 + 内置 helper），命名 `loveace-{version}-win-x64.zip`。
- **安装器**：维持现有 `loveace-{version}-setup.exe`（兜底路用）。
- 两者同一次 CI 产出、一起上传，互不替代。
- **不做 delta**（全量快照让普通贡献者改动零负担，见 §10）。

### 5.2 manifest schema 演进（加字段，向后兼容）

现 `PlatformRelease` 字段：`version / force_ota / url / md5 / type`。扩展为：

```jsonc
"windows": {
  "version": "1.1.12",
  "force_ota": false,
  "type": "native",
  "url": ".../loveace-1.1.12-setup.exe",   // 安装器（兜底）
  "md5": "...",                            // 兼容旧客户端，仅防下载损坏
  "sha256": "...",                         // 安装器 sha256（新增）
  "package": {                             // 新增：内部替换包（可选）
    "url": ".../loveace-1.1.12-win-x64.zip",
    "sha256": "...",
    "enabled": true                        // 远程 kill-switch，见 §9 修正D
  }
}
```

- 旧客户端忽略 `package`/`sha256` → 自动只走安装器，**向后兼容**。
- `package` 缺失或 `enabled=false` → 新客户端自动降级安装器。

---

## 第 6 部分　核心流程：内部替换 + 重启

正在运行的 `loveace.exe` 无法替换自身，必须外部 helper。

### 6.1 流程（9 步）
```
1. 决策为「内部替换」（§3）
2. dio 下载 zip → 临时目录（复用 windows_update_service 下载链路）
3. 校验整包 sha256（失败：删包 + 提示，结束）
4. 解压到 staging：%LOCALAPPDATA%\LoveACE\update_staging\{version}\
5. 解压后健全性检查：staging 内必须存在 loveace.exe 且大小 > 0
6. 写 update journal(JSON)：{from, to, install_dir, staging_dir, backup_dir, state:"pending"}
7. 启动内置 helper（loveace_updater.exe），detached，传 journal 路径
8. 主应用退出
9. helper 执行：
     a. 等待 loveace.exe 进程退出（轮询 + 超时保护，超时则回滚+提示，绝不强杀）
     b. rename install_dir → backup_dir         （目录改名，原子、快）
     c. rename staging_dir → install_dir
     d. 成功 → journal.state="done"，启动新 loveace.exe，删 backup_dir
     e. 任一步失败 → rename backup_dir → install_dir 回滚，journal.state="failed"
10. 新应用启动读 journal：
     - done            → 清理 journal/残留
     - failed/pending  → 提示「更新未完成已回滚」，保留兜底入口（再走安装器路）
```

### 6.2 helper 形态（已按可维护性定稿）
- 用 **`dart compile exe`** 产出独立 `loveace_updater.exe`，**不开 C++/Rust 原生子工程**。
- 理由：仓库已是 Flutter/Dart 工具链，helper 只需 `dart:io`（等待进程、目录改名、重启、读写 journal），任何现有贡献者都能改，不引入第二套语言/构建系统。
- **不用运行时生成 .bat**（杀进程+换 exe 的 .bat 最易被杀软/组织策略拦截）。
- helper 必须能被同一证书签名（§7.1）。
- helper 只做**整目录改名**，对安装内部文件布局无知 → 布局变化不需要改 helper。

---

## 第 7 部分　签名 / 权限 / 回滚 / 失败恢复

### 7.1 代码签名（明确不采购，按「无签名」设计）
- 现状 Windows 端**零签名**（CI 无 signtool、仓库无 .pfx）。
- **决策：本项目为学生自发开源、同学自用，不采购任何付费证书（EV/OV）。** 接受其后果，不为它停工。
- 后果（必须如实告知用户，不要承诺消除）：
  - 安装器 / exe 的 **SmartScreen、未知发布者提示无法消除**，任何 OTA 方案都改变不了。首次安装/更新仍可能需要用户点「仍要运行」。
  - 内部替换 helper 会「杀进程 + 替换 exe」，**未签名时被杀软误报/隔离的概率最高**——这是 Phase 3 相对其它阶段独有的、且无法靠工程消除的风险。
- 因此，**Phase 3（内部替换）默认用 §9 修正 D 的 kill-switch 关闭**，作为可选增强，想做时小范围灰度验证杀软表现；不作为达标必需。
- 真正不依赖签名、又能改善体验的是 **Phase 2（装到 `%LOCALAPPDATA%`）**：免费、改一处 iss、直接免掉更新时的 UAC——这是本项目性价比最高的一步。

### 7.2 权限
- 内部替换仅在 install dir 可写时进行 → 不需要 admin，无 UAC。
- 兜底安装器路保持现状：Inno setup.exe 引导层自行 ShellExecute "runas" 自提权。
  ⚠️ `Process.start` 经 CreateProcess 本身不自动提权，靠 Inno 自身——**此自提权链路实施时需实测确认一次**。
- 方案要求：内部替换绝不尝试在不可写目录（Program Files）强行覆盖，一律降级安装器。

### 7.3 校验（SHA256 全链路，需改 4 处保持一致）
1. `android/tools/publish/manifest.py` — `PlatformRelease` 加 `sha256`，OTA 平台节点支持 `package`
2. `android/tools/publish/cli.py` — 计算 zip/安装器 sha256（仿 `:35-41` 的 md5 函数）；release 命令增产 zip 上传
3. `desktop/lib/models/manifest_model.dart` — 加 `sha256` + `package` 字段，**重新生成 `manifest_model.g.dart`**
4. `desktop/lib/services/windows_update_service.dart` — 校验 sha256（仿现有 md5 校验 `:85-96`）
- MD5 字段保留，仅兼容旧客户端 + 防下载损坏，不作安全校验。

### 7.4 回滚 / 失败恢复
- 替换前 backup（目录改名，非拷贝，快且原子性好）。
- helper 任一步失败 → rename backup 回 install dir 回滚。
- 崩溃中断 → 靠 update journal：新应用启动检测状态非 done → 提示 + 保留兜底入口。
- 安装器路的「回滚」依赖安装器与用户操作，无需额外工程。

---

## 第 8 部分　分阶段落地计划（含文件级改动）

每个 Phase 都是**可独立合并、可独立回退**的 PR。

### Phase 0 — 验收既有方案 A（非开发）
- 端到端实测：下载→校验→UAC 自提权→`/CLOSEAPPLICATIONS` 关应用→覆盖→重启。
- 补单测：md5 不匹配删文件 / URL 非法 / 非 native 拒绝。
- 确认 Windows 走 `winui_ota_dialog`（若 Material 版 `ota_update_dialog.dart` 也覆盖 Windows，需同步逻辑——见 §9 修正 B 一并处理）。
- 改动：仅测试。

### Phase 1 — SHA256 全链路（低风险，先行）
- 改动 4 文件（§7.3）。纯增字段 + 校验，向后兼容。

### Phase 2 — 用户级安装（内部替换前置）
- `inno-ci.iss`：`DefaultDirName` → `{localappdata}\Programs\LoveACE` + `PrivilegesRequired=lowest`。
- 加 per-user/per-machine 双版本检测提示（不静默清理）。
- 改动：`inno-ci.iss` + 少量启动期检测代码。

### Phase 3 — 内部替换主路
- CI：增产 `loveace-{version}-win-x64.zip` + 上传 + manifest 写 `package`
  （`build-desktop-windows.yml` / `cli.py` / `manifest.py`）。
- 新建 helper 子工程：`dart compile exe` → `loveace_updater.exe`，打进安装包与 zip。
- `windows_update_service.dart`：增「可写检测 + 解压 staging + 写 journal + 拉起 helper」分支。
- 更新决策逻辑收敛为纯函数（§9 修正 B），对话框接入三态。
- 启动期 journal 恢复检查。
- 改动：新增 helper + service 扩展 + CI 扩展 + 启动检查。

**依赖关系**：Phase 3 依赖 Phase 1（sha256）与 Phase 2（可写目录）。Phase 0/1 可立即做。

---

## 第 9 部分　多人协作可维护性约束（硬约束，与上文冲突以本节为准）

OTA 是「改错了用户更新不了、又无法用 OTA 自救」的高风险路径，开源项目尤甚。以下为强制护栏：

**修正 A — helper 用 Dart 编译，不开原生子工程。**（已并入 §6.2）统一工具链，降低贡献门槛。

**修正 B — 更新决策逻辑单点，UI 保持薄。**
- 决策（可写检测 → 内部替换/安装器/复制链接）放进 `WindowsUpdateService` 或独立纯函数，返回枚举 `UpdateStrategy.inPlace / installer / copyLink`。
- `winui_ota_dialog.dart` 只**消费**结果渲染按钮，不在 UI 里判断。
- ⚠️ `widgets/ota_update_dialog.dart`（Material 版 `OTAUpdateDialog`）是**死代码**（全项目无调用），desktop 只走 `WinUIOTADialog`。**无需同步它**；如要清理，单独提一个删除 PR，不要混进本方案。

**修正 C — manifest schema 是「双语言契约」，必须显式保护。**
- `manifest.py`（Python）与 `manifest_model.dart`（Dart）顶部各加注释互指「改本模型须同步另一端」。
- 增契约测试：一份样例 manifest JSON 同喂两端模型，断言关键字段都能解析；放进 CI，字段漂移即红灯。
- 在 `notes/` 或 CONTRIBUTING 写明 manifest 字段清单与两端文件位置。

**修正 D — 远程 kill-switch。**
- manifest `package.enabled`（§5.2）：false 时客户端强制走安装器兜底，即使包齐全。
- 线上内部替换出问题，改 manifest（一次发布脚本调用）即可全量关闭，无需发新客户端。
- 与能力探测叠加：探测决定「能不能」，开关决定「准不准」。

**修正 E — Windows 特有逻辑隔离。**
- 内部替换 / helper / 可写检测全部 `Platform.isWindows` 守卫，集中在 `windows_update_service.dart` 与 helper 子目录，不往 `manifest_provider` / 通用 UI 塞平台分支。
- 延续现有范式 `windows_update_service.dart:41 isSupported => Platform.isWindows`。

**修正 F — 每 Phase 自洽、可回退、自带测试与文档。**
- 高风险 Phase 3 必须带单测（sha256 校验、journal 状态机、可写检测降级）+ 一段「OTA 工作原理」说明。
- 评审者无 Windows 环境时，靠测试 + 文档 + kill-switch 建立信心。

**修正 G — 发布工具链门槛写清。**
- 发布脚本在 `android/tools/publish/`（Windows 包发布逻辑住在 android 目录，反直觉），文档点明。
- 保持 `build-desktop-windows.yml` 的 `dry_run` 可用，让贡献者不碰 secrets 即可验证打包+manifest。
- 不扩大 CI secret 暴露面；签名密钥走 secret/HSM，绝不入库。

---

## 第 10 部分　贡献者发布 Runbook（普通改动零 OTA 负担）

**正常加功能 / 修 bug（纯 Dart 改动），贡献者只需：**
```
1. 写代码
2. 改 desktop/pubspec.yaml 版本号   ← 唯一必须记住的（不改则客户端检测不到更新）
3. 触发发布 workflow
完事。CI 自动产 zip + 安装器、算 sha256、写 manifest。
```
零 OTA 负担的原因：全量包快照 + 安装器通配符收文件 + 客户端能力探测，三者吸收所有普通改动。

**只有这些「非普通」改动才需要额外动作：**

| 改动 | 需要做什么 | 护栏 |
| --- | --- | --- |
| 改构建产物文件布局（新增非 `data/` 下的文件/文件夹、新加独立 exe） | 同步 `inno-ci.iss` 的 `[Files]` | 现在就需要，非 OTA 新增 |
| 改 manifest schema（加 OTA 字段） | 同步 `manifest.py` + `manifest_model.dart` 两端 | 契约测试红灯兜底（修正 C） |
| 新增二进制 | 纳入签名 | 项目级配置 |
| 改 helper 逻辑本身 | 注意执行本次更新的是**旧版 helper**，修复下次更新才生效 | 文档点明 |

**安全垫**：漏产 zip / manifest 没写 `package` → 客户端自动退回跑安装器，更新不会失败，只降级。

---

## 第 11 部分　决策点（已全部定稿）

1. **范围与红线**：✅ 范围 = Desktop Windows Release / CI；红线 = 不影响非 Windows 平台运行时；采路线甲（共享模型加惰性可选字段）+ 回归测试（§2.1）。
2. **代码签名**：✅ **不采购任何付费证书**，按无签名设计。后果（SmartScreen 不可消除、Phase 3 helper 有杀软误报风险）已接受（§7.1）。
3. **交付范围**：✅ **完整闭掉 Issue #6，Phase 1+2+3 全做。**
4. **Phase 3 上线策略**：✅ 代码完整提交，但 **kill-switch 默认关闭**，灰度验证杀软表现后再开启。
5. **PR 形态**：✅ **一个完整 PR 全交**，内部按 Phase 1→2→3 分 commit。

—— 决策点已全部明确，可直接交付实施。

---

## 附录　实施者快速索引

- 下载/校验/启动核心服务：`desktop/lib/services/windows_update_service.dart`
- OTA 对话框（Windows）：`desktop/lib/winui/widgets/winui_ota_dialog.dart`
- 版本判断/平台：`desktop/lib/providers/manifest_provider.dart`
- 数据模型（Dart / Python）：`desktop/lib/models/manifest_model.dart` / `android/tools/publish/manifest.py`
- 安装器脚本：`desktop/windows/inno-ci.iss`
- CI：`.github/workflows/build-desktop-windows.yml`
- 发布脚本：`android/tools/publish/cli.py`
- helper（新建）：建议 `desktop/windows/updater/`（Dart 子工程）→ 产 `loveace_updater.exe`
