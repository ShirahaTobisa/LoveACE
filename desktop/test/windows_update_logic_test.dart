import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loveace/models/manifest_model.dart';
import 'package:loveace/providers/manifest_provider.dart';
import 'package:loveace/services/file_hash_service.dart';
import 'package:loveace/services/windows_update_journal.dart';
import 'package:loveace/services/windows_update_strategy.dart';

void main() {
  group('FileHashService', () {
    test('sha256 matches known content', () async {
      final file = await _tempFile('loveace');
      addTearDown(() => file.parent.delete(recursive: true));

      expect(
        await FileHashService.sha256Hex(file),
        '164c799f61afb7d2294dc17f13498048da8cdcd723e384bc46c6cf98b4829b9d',
      );
    });

    test('sha256 detects damaged content', () async {
      final file = await _tempFile('loveace');
      addTearDown(() => file.parent.delete(recursive: true));

      final original = await FileHashService.sha256Hex(file);
      await file.writeAsString('loveace-damaged');

      expect(await FileHashService.sha256Hex(file), isNot(original));
    });
  });

  group('ManifestProvider version comparison', () {
    test('detects newer semantic versions', () {
      expect(ManifestProvider.isNewerVersion('1.1.12', '1.1.11'), isTrue);
      expect(ManifestProvider.isNewerVersion('1.2.0', '1.1.99'), isTrue);
      expect(ManifestProvider.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(ManifestProvider.isNewerVersion('1.1.11', '1.1.11'), isFalse);
      expect(ManifestProvider.isNewerVersion('1.1.10', '1.1.11'), isFalse);
    });
  });

  group('UpdateStrategy', () {
    final package = UpdatePackage(
      url: 'https://example.com/loveace.zip',
      sha256: 'abc',
      enabled: true,
    );

    test('uses in-place when Windows, writable and package is enabled', () {
      final release = _release(package: package, sha256: 'installer-sha');

      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: true,
            installDirWritable: true,
          ),
        ),
        UpdateStrategy.inPlace,
      );
    });

    test('falls back to installer after in-place failed for same version', () {
      final release = _release(package: package, sha256: 'installer-sha');

      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: true,
            installDirWritable: true,
            failedInPlaceVersion: '1.1.12',
          ),
        ),
        UpdateStrategy.installer,
      );
    });

    test('uses in-place again when manifest advances past failed version', () {
      final release = _release(package: package, sha256: 'installer-sha');

      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: true,
            installDirWritable: true,
            failedInPlaceVersion: '1.1.11',
          ),
        ),
        UpdateStrategy.inPlace,
      );
    });

    test('falls back to installer when package kill-switch is off', () {
      final release = _release(
        package: UpdatePackage(
          url: 'https://example.com/loveace.zip',
          sha256: 'abc',
        ),
        sha256: 'installer-sha',
      );

      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: true,
            installDirWritable: true,
          ),
        ),
        UpdateStrategy.installer,
      );
    });

    test('falls back to installer when install dir is not writable', () {
      final release = _release(package: package, sha256: 'installer-sha');

      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: true,
            installDirWritable: false,
          ),
        ),
        UpdateStrategy.installer,
      );
    });

    test('copies link when not Windows or missing validation', () {
      final release = _release(md5: '', sha256: '');

      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: false,
            installDirWritable: true,
          ),
        ),
        UpdateStrategy.copyLink,
      );
      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: true,
            installDirWritable: true,
          ),
        ),
        UpdateStrategy.copyLink,
      );
    });

    test('does not use in-place package on non-Windows platforms', () {
      final release = _release(
        package: package,
        sha256: 'installer-sha',
      );

      expect(
        decideWindowsUpdateStrategy(
          release: release,
          capabilities: const WindowsUpdateCapabilities(
            isWindows: false,
            installDirWritable: true,
          ),
        ),
        UpdateStrategy.copyLink,
      );
    });
  });

  group('WindowsUpdateJournal', () {
    test('round trips pending to done', () {
      final pending = _journal(WindowsUpdateJournalState.pending);
      final decoded = WindowsUpdateJournal.fromJsonString(pending.toJsonString());

      expect(decoded.state, WindowsUpdateJournalState.pending);
      expect(
        decoded.stagingDir,
        r'C:\Users\a\AppData\Local\Programs\.loveace_update_staging_1.1.12',
      );
      expect(
        decoded.backupDir,
        r'C:\Users\a\AppData\Local\Programs\.loveace_update_backup_1.1.11_to_1.1.12',
      );
      expect(
        decoded.copyWith(state: WindowsUpdateJournalState.done).state,
        WindowsUpdateJournalState.done,
      );
    });

    test('round trips failed rollback state with error', () {
      final failed = _journal(
        WindowsUpdateJournalState.failed,
        error: 'rollback',
      );
      final decoded = WindowsUpdateJournal.fromJsonString(failed.toJsonString());

      expect(decoded.state, WindowsUpdateJournalState.failed);
      expect(decoded.error, 'rollback');
    });
  });

  group('manifest parsing', () {
    test('parses new Windows package fields', () {
      final manifest = LoveACEManifest.fromJson(_manifestJson(
        windowsExtra: {
          'sha256': 'installer-sha',
          'package': {
            'url': 'https://example.com/loveace.zip',
            'sha256': 'package-sha',
            'enabled': true,
          },
        },
      ));

      final windows = manifest.ota!.windows!;
      expect(windows.sha256, 'installer-sha');
      expect(windows.package!.enabled, isTrue);
      expect(windows.package!.sha256, 'package-sha');
    });

    test('serializes new Windows package fields', () {
      final manifest = LoveACEManifest.fromJson(_manifestJson(
        windowsExtra: {
          'sha256': 'installer-sha',
          'package': {
            'url': 'https://example.com/loveace.zip',
            'sha256': 'package-sha',
            'enabled': false,
          },
        },
      ));

      final json = manifest.toJson();
      final ota = json['ota'] as Map<String, dynamic>;
      final windows = ota['windows'] as Map<String, dynamic>;
      final package = windows['package'] as Map<String, dynamic>;

      expect(windows['sha256'], 'installer-sha');
      expect(package['url'], 'https://example.com/loveace.zip');
      expect(package['sha256'], 'package-sha');
      expect(package['enabled'], isFalse);
    });

    test('old manifest without new fields still parses', () {
      final manifest = LoveACEManifest.fromJson(_manifestJson());
      final windows = manifest.ota!.windows!;

      expect(windows.sha256, '');
      expect(windows.package, isNull);
      expect(windows.md5, 'old-md5');
    });

    test('non-Windows platform node is not affected by Windows fields', () {
      final manifest = LoveACEManifest.fromJson(_manifestJson(
        windowsExtra: {
          'sha256': 'installer-sha',
          'package': {
            'url': 'https://example.com/loveace.zip',
            'sha256': 'package-sha',
            'enabled': true,
          },
        },
      ));

      final android = manifest.ota!.android!;
      expect(android.version, '1.1.12');
      expect(android.url, 'https://example.com/app.apk');
      expect(android.sha256, '');
      expect(android.package, isNull);
    });
  });

}

PlatformRelease _release({
  String md5 = 'installer-md5',
  String sha256 = '',
  UpdatePackage? package,
}) {
  return PlatformRelease(
    version: '1.1.12',
    forceOta: false,
    url: 'https://example.com/loveace.exe',
    md5: md5,
    sha256: sha256,
    package: package,
  );
}

WindowsUpdateJournal _journal(
  WindowsUpdateJournalState state, {
  String? error,
}) {
  return WindowsUpdateJournal(
    fromVersion: '1.1.11',
    toVersion: '1.1.12',
    installDir: r'C:\Users\a\AppData\Local\Programs\LoveACE',
    stagingDir: r'C:\Users\a\AppData\Local\Programs\.loveace_update_staging_1.1.12',
    backupDir: r'C:\Users\a\AppData\Local\Programs\.loveace_update_backup_1.1.11_to_1.1.12',
    state: state,
    error: error,
  );
}

Map<String, dynamic> _manifestJson({Map<String, dynamic>? windowsExtra}) {
  final manifest = jsonDecode('''
{
  "ota": {
    "content": "update",
    "changelog": [{"version": "1.1.12", "changes": "fix"}],
    "windows": {
      "version": "1.1.12",
      "force_ota": false,
      "url": "https://example.com/loveace.exe",
      "md5": "old-md5",
      "type": "native"
    },
    "android": {
      "version": "1.1.12",
      "force_ota": false,
      "url": "https://example.com/app.apk",
      "md5": "android-md5",
      "type": "native"
    }
  }
}
''') as Map<String, dynamic>;
  final ota = manifest['ota'] as Map<String, dynamic>;
  final windows = ota['windows'] as Map<String, dynamic>;
  windows.addAll(windowsExtra ?? {});
  return manifest;
}

Future<File> _tempFile(String content) async {
  final dir = await Directory.systemTemp.createTemp('loveace_hash_test_');
  final file = File('${dir.path}${Platform.pathSeparator}payload.txt');
  return file.writeAsString(content);
}
