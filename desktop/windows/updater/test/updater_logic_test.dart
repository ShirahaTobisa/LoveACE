import 'dart:io';

import 'package:test/test.dart';
import 'package:loveace_updater/inno_uninstaller.dart';
import 'package:loveace_updater/update_journal.dart';
import 'package:loveace_updater/update_plan.dart';

void main() {
  test('journal round trips pending to done', () {
    final journal = _journal(UpdateJournalState.pending);
    final decoded = UpdateJournal.fromJsonString(journal.toJsonString());

    expect(decoded.state, UpdateJournalState.pending);
    expect(
      decoded.copyWith(state: UpdateJournalState.done).state,
      UpdateJournalState.done,
    );
  });

  test('journal round trips failed rollback state with error', () {
    final journal = _journal(UpdateJournalState.failed, error: 'rollback');
    final decoded = UpdateJournal.fromJsonString(journal.toJsonString());

    expect(decoded.state, UpdateJournalState.failed);
    expect(decoded.error, 'rollback');
  });

  test('builds directory rename plan from journal', () {
    final journal = _journal(UpdateJournalState.pending);
    final plan = buildUpdatePlan(journal);

    expect(plan.installDir.path, journal.installDir);
    expect(plan.stagingDir.path, journal.stagingDir);
    expect(plan.backupDir.path, journal.backupDir);
    expect(plan.newExecutable.path.endsWith('loveace.exe'), isTrue);
  });

  test('rejects staging and backup outside install parent', () async {
    final root = await Directory.systemTemp.createTemp('loveace_updater_test_');
    addTearDown(() => root.delete(recursive: true));
    final installDir = Directory('${root.path}${Platform.pathSeparator}LoveACE');
    final stagingDir = Directory('${root.path}${Platform.pathSeparator}other${Platform.pathSeparator}staging');
    final backupDir = Directory('${root.path}${Platform.pathSeparator}backup');
    await installDir.create(recursive: true);
    await stagingDir.create(recursive: true);
    await File('${stagingDir.path}${Platform.pathSeparator}loveace.exe').writeAsString('exe');

    await expectLater(
      validatePlan(UpdatePlan(
        installDir: installDir,
        stagingDir: stagingDir,
        backupDir: backupDir,
        newExecutable: File('${stagingDir.path}${Platform.pathSeparator}loveace.exe'),
      )),
      throwsStateError,
    );
  });

  test('copies top-level Inno uninstaller files into staging', () async {
    final root = await Directory.systemTemp.createTemp('loveace_updater_test_');
    addTearDown(() => root.delete(recursive: true));
    final backupDir = Directory('${root.path}${Platform.pathSeparator}backup');
    final stagingDir = Directory(
      '${root.path}${Platform.pathSeparator}staging',
    );
    final nestedDir = Directory(
      '${backupDir.path}${Platform.pathSeparator}nested',
    );
    await nestedDir.create(recursive: true);
    await File(
      '${backupDir.path}${Platform.pathSeparator}unins000.exe',
    ).writeAsString('exe');
    await File(
      '${backupDir.path}${Platform.pathSeparator}unins000.dat',
    ).writeAsString('dat');
    await File(
      '${backupDir.path}${Platform.pathSeparator}unins001.txt',
    ).writeAsString('txt');
    await File(
      '${nestedDir.path}${Platform.pathSeparator}unins999.exe',
    ).writeAsString('nested');

    final result = await copyInnoUninstallerFiles(
      from: backupDir,
      to: stagingDir,
    );

    expect(result.copiedCount, 2);
    expect(
      await File(
        '${stagingDir.path}${Platform.pathSeparator}unins000.exe',
      ).readAsString(),
      'exe',
    );
    expect(
      await File(
        '${stagingDir.path}${Platform.pathSeparator}unins000.dat',
      ).readAsString(),
      'dat',
    );
    expect(
      await File(
        '${stagingDir.path}${Platform.pathSeparator}unins001.txt',
      ).exists(),
      isFalse,
    );
    expect(
      await File(
        '${stagingDir.path}${Platform.pathSeparator}unins999.exe',
      ).exists(),
      isFalse,
    );
  });

  test('does not fail when Inno uninstaller files are missing', () async {
    final root = await Directory.systemTemp.createTemp('loveace_updater_test_');
    addTearDown(() => root.delete(recursive: true));
    final backupDir = Directory('${root.path}${Platform.pathSeparator}backup');
    final stagingDir = Directory(
      '${root.path}${Platform.pathSeparator}staging',
    );
    await backupDir.create(recursive: true);

    final result = await copyInnoUninstallerFiles(
      from: backupDir,
      to: stagingDir,
    );

    expect(result.foundFiles, isFalse);
    expect(await stagingDir.exists(), isTrue);
  });
}

UpdateJournal _journal(UpdateJournalState state, {String? error}) {
  return UpdateJournal(
    fromVersion: '1.1.11',
    toVersion: '1.1.12',
    installDir: '${Directory.systemTemp.path}${Platform.pathSeparator}LoveACE',
    stagingDir: '${Directory.systemTemp.path}${Platform.pathSeparator}.loveace_update_staging_1.1.12',
    backupDir: '${Directory.systemTemp.path}${Platform.pathSeparator}.loveace_update_backup_1.1.11_to_1.1.12',
    state: state,
    error: error,
  );
}
