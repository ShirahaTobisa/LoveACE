import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../models/manifest_model.dart';
import 'file_hash_service.dart';
import 'logger_service.dart';
import 'windows_update_journal.dart';

class WindowsUpdateException implements Exception {
  final String message;

  const WindowsUpdateException(this.message);

  @override
  String toString() => message;
}

class WindowsUpdateDownloadResult {
  final File installer;
  final String hash;

  const WindowsUpdateDownloadResult({
    required this.installer,
    required this.hash,
  });
}

class WindowsPackagePrepareResult {
  final File journalFile;
  final Directory stagingDir;

  const WindowsPackagePrepareResult({
    required this.journalFile,
    required this.stagingDir,
  });
}

class WindowsUpdateService {
  WindowsUpdateService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static bool get isSupported => Platform.isWindows;

  static Future<WindowsUpdateDownloadResult> downloadInstaller({
    required PlatformRelease release,
    required void Function(int received, int total) onProgress,
  }) async {
    _ensureWindows();
    if (release.type.toLowerCase() != 'native') {
      throw const WindowsUpdateException('当前更新不是原生安装包');
    }
    if (release.url.isEmpty) {
      throw const WindowsUpdateException('更新下载地址为空');
    }
    if (release.sha256.isEmpty && release.md5.isEmpty) {
      throw const WindowsUpdateException('安装包缺少校验值，已取消更新');
    }

    final uri = _parseUri(release.url);
    final installer = File(
      p.join((await _updatesDir()).path, _installerFileName(uri, release.version)),
    );
    await _deleteIfExists(installer);

    LoggerService.info('⬇️ 开始下载 Windows 更新安装器: ${release.url}');
    await _dio.download(
      release.url,
      installer.path,
      onReceiveProgress: onProgress,
      options: Options(followRedirects: true),
    );

    final actualHash = await _verifyInstaller(installer, release);
    LoggerService.info('✅ Windows 更新安装器下载完成: ${installer.path}');
    return WindowsUpdateDownloadResult(installer: installer, hash: actualHash);
  }

  static Future<WindowsPackagePrepareResult> prepareInPlacePackage({
    required PlatformRelease release,
    required String currentVersion,
    required void Function(int received, int total) onProgress,
  }) async {
    _ensureWindows();
    final package = release.package;
    if (package == null || !package.enabled) {
      throw const WindowsUpdateException('内部替换更新未启用');
    }
    if (package.url.isEmpty || package.sha256.isEmpty) {
      throw const WindowsUpdateException('内部替换更新包信息不完整');
    }
    if (!await isInstallDirectoryWritable()) {
      throw const WindowsUpdateException('当前安装目录不可写，无法内部替换');
    }

    final uri = _parseUri(package.url);
    final updatesDir = await _updatesDir();
    final packageFile = File(
      p.join(updatesDir.path, _packageFileName(uri, release.version)),
    );
    await _deleteIfExists(packageFile);

    LoggerService.info('⬇️ 开始下载 Windows 内部更新包: ${package.url}');
    await _dio.download(
      package.url,
      packageFile.path,
      onReceiveProgress: onProgress,
      options: Options(followRedirects: true),
    );

    final actualSha256 = await FileHashService.sha256Hex(packageFile);
    if (actualSha256.toLowerCase() != package.sha256.toLowerCase()) {
      await _deleteIfExists(packageFile);
      throw WindowsUpdateException(
        '更新包 SHA256 校验失败：期望 ${package.sha256}，实际 $actualSha256',
      );
    }

    final installDir = await currentInstallDirectory();
    final stagingRoot = Directory(
      p.join(installDir.parent.path, '.loveace_update_staging_${_safeSegment(release.version)}'),
    );
    await _deleteDirIfExists(stagingRoot);
    await stagingRoot.create(recursive: true);
    await _expandZip(packageFile, stagingRoot);

    final stagedExe = File(p.join(stagingRoot.path, 'loveace.exe'));
    if (!await stagedExe.exists() || await stagedExe.length() <= 0) {
      throw const WindowsUpdateException('更新包无效：未找到 loveace.exe');
    }

    final backupDir = Directory(
      p.join(
        installDir.parent.path,
        '.loveace_update_backup_${_safeSegment(currentVersion)}_to_${_safeSegment(release.version)}',
      ),
    );
    await _deleteDirIfExists(backupDir);

    final journal = WindowsUpdateJournal(
      fromVersion: currentVersion,
      toVersion: release.version,
      installDir: installDir.path,
      stagingDir: stagingRoot.path,
      backupDir: backupDir.path,
      state: WindowsUpdateJournalState.pending,
    );
    final journalFile = await _journalFile();
    await journalFile.parent.create(recursive: true);
    await journalFile.writeAsString(journal.toJsonString());

    return WindowsPackagePrepareResult(
      journalFile: journalFile,
      stagingDir: stagingRoot,
    );
  }

  static Future<void> launchInstaller(File installer) async {
    _ensureWindows();
    if (!await installer.exists()) {
      throw const WindowsUpdateException('安装器文件不存在');
    }

    LoggerService.info('🚀 启动 Windows 更新安装器: ${installer.path}');
    await Process.start(
      installer.path,
      const [
        '/SP-',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  static Future<void> launchHelper(File journalFile) async {
    _ensureWindows();
    final installDir = await currentInstallDirectory();
    final helperSource = File(p.join(installDir.path, 'loveace_updater.exe'));
    if (!await helperSource.exists()) {
      throw const WindowsUpdateException('更新 helper 不存在，无法内部替换');
    }
    final updatesDir = await _updatesDir();
    final helper = File(p.join(updatesDir.path, 'loveace_updater.exe'));
    await _deleteIfExists(helper);
    await helperSource.copy(helper.path);

    LoggerService.info('🚀 启动 Windows 更新 helper: ${helper.path}');
    await Process.start(
      helper.path,
      [journalFile.path],
      mode: ProcessStartMode.detached,
      workingDirectory: updatesDir.path,
    );
  }

  static Future<Directory> currentInstallDirectory() async {
    _ensureWindows();
    return File(Platform.resolvedExecutable).parent;
  }

  static Future<bool> isInstallDirectoryWritable() async {
    if (!Platform.isWindows) return false;
    final dir = await currentInstallDirectory();
    final probe = File(
      p.join(dir.path, '.loveace_update_probe_${DateTime.now().microsecondsSinceEpoch}'),
    );
    final parentProbe = Directory(
      p.join(dir.parent.path, '.loveace_update_parent_probe_${DateTime.now().microsecondsSinceEpoch}'),
    );
    try {
      await probe.writeAsString('probe');
      await probe.delete();
      await parentProbe.create();
      await parentProbe.delete();
      return true;
    } catch (_) {
      await _deleteIfExists(probe);
      await _deleteDirIfExists(parentProbe);
      return false;
    }
  }

  static Future<WindowsUpdateJournal?> readJournal() async {
    if (!Platform.isWindows) return null;
    final file = await _journalFile();
    if (!await file.exists()) return null;
    try {
      return WindowsUpdateJournal.fromJsonString(await file.readAsString());
    } catch (e) {
      LoggerService.error('❌ 读取 Windows 更新 journal 失败', error: e);
      return null;
    }
  }

  static Future<void> clearJournal() async {
    if (!Platform.isWindows) return;
    await _deleteIfExists(await _journalFile());
  }

  static Future<void> clearUpdateCache() async {
    if (!Platform.isWindows) return;
    try {
      final cacheDir = await getTemporaryDirectory();
      final updatesDir = Directory(p.join(cacheDir.path, 'loveace_updates'));
      if (!await updatesDir.exists()) return;
      await for (final entity in updatesDir.list(followLinks: false)) {
        try {
          if (entity is Directory) {
            await entity.delete(recursive: true);
          } else {
            await entity.delete();
          }
        } catch (e) {
          LoggerService.warning(
            '⚠️ 清理 Windows OTA 缓存失败: ${entity.path}',
            error: e,
          );
        }
      }
    } catch (e) {
      LoggerService.warning(
        '⚠️ 读取 Windows OTA 缓存目录失败',
        error: e,
      );
    }
  }

  static Future<String> _verifyInstaller(
    File installer,
    PlatformRelease release,
  ) async {
    if (release.sha256.isNotEmpty) {
      final actualSha256 = await FileHashService.sha256Hex(installer);
      if (actualSha256.toLowerCase() != release.sha256.toLowerCase()) {
        await _deleteIfExists(installer);
        throw WindowsUpdateException(
          '安装包 SHA256 校验失败：期望 ${release.sha256}，实际 $actualSha256',
        );
      }
      return actualSha256;
    }

    final actualMd5 = await FileHashService.md5Hex(installer);
    if (actualMd5.toLowerCase() != release.md5.toLowerCase()) {
      await _deleteIfExists(installer);
      throw WindowsUpdateException(
        '安装包 MD5 校验失败：期望 ${release.md5}，实际 $actualMd5',
      );
    }
    return actualMd5;
  }

  static Future<Directory> _updatesDir() async {
    final cacheDir = await getTemporaryDirectory();
    final updateDir = Directory(p.join(cacheDir.path, 'loveace_updates'));
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }
    return updateDir;
  }

  static Future<File> _journalFile() async {
    final supportDir = await getApplicationSupportDirectory();
    return File(p.join(supportDir.path, 'windows_update_journal.json'));
  }

  static Uri _parseUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw const WindowsUpdateException('更新下载地址无效');
    }
    return uri;
  }

  static String _installerFileName(Uri uri, String version) {
    final fromUrl = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (fromUrl.toLowerCase().endsWith('.exe')) {
      return fromUrl;
    }
    return 'loveace-$version-setup.exe';
  }

  static String _packageFileName(Uri uri, String version) {
    final fromUrl = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (fromUrl.toLowerCase().endsWith('.zip')) {
      return fromUrl;
    }
    return 'loveace-$version-win-x64.zip';
  }

  static String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  static Future<void> _expandZip(File packageFile, Directory targetDir) async {
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'& { param($zipPath, $destinationPath) Expand-Archive -LiteralPath $zipPath -DestinationPath $destinationPath -Force }',
        packageFile.path,
        targetDir.path,
      ],
    );
    if (result.exitCode != 0) {
      throw WindowsUpdateException(
        '更新包解压失败：${result.stderr}'.trim(),
      );
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<void> _deleteDirIfExists(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  static void _ensureWindows() {
    if (!Platform.isWindows) {
      throw const WindowsUpdateException('当前平台不支持 Windows 安装器更新');
    }
  }

  // TODO: 人工验证 - UAC 自提权、杀软反应、真实替换重启、SmartScreen 表现。
  static String get manualVerificationNote =>
      'TODO: 人工验证 - UAC 自提权、杀软反应、真实替换重启、SmartScreen 表现。'
      ' ${AppConstants.appName} 不承诺消除 SmartScreen。';
}
