import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:loveace_updater/update_journal.dart';
import 'package:loveace_updater/update_plan.dart';

// TODO: 人工验证 - 杀软反应、真实替换重启、SmartScreen 表现。

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: loveace_updater.exe <journal.json>');
    exitCode = 2;
    return;
  }

  final journalFile = File(args.single);
  try {
    final journal = UpdateJournal.fromJsonString(await journalFile.readAsString());
    final plan = buildUpdatePlan(journal);
    await validatePlan(plan);
    await _waitForMainProcessToExit(plan.installDir);
    await _replaceInstallDir(plan);
    await journalFile.writeAsString(
      journal.copyWith(state: UpdateJournalState.done).toJsonString(),
    );
    await Process.start(
      p.join(plan.installDir.path, 'loveace.exe'),
      const <String>[],
      mode: ProcessStartMode.detached,
      workingDirectory: plan.installDir.path,
    );
    await _deleteDirectory(plan.backupDir);
  } catch (e) {
    try {
      await _rollback(journalFile, e);
    } catch (rollbackError) {
      stderr.writeln('Rollback failed: $rollbackError');
    }
    exitCode = 1;
  }
}

Future<void> _waitForMainProcessToExit(Directory installDir) async {
  final exePath = p.join(installDir.path, 'loveace.exe').toLowerCase();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'Get-Process loveace -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path',
      ],
    );
    final runningPaths = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim().toLowerCase())
        .where((line) => line.isNotEmpty);
    if (!runningPaths.contains(exePath)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('loveace.exe did not exit before update timeout');
}

Future<void> _replaceInstallDir(UpdatePlan plan) async {
  await _deleteDirectory(plan.backupDir);
  await plan.backupDir.parent.create(recursive: true);
  await plan.installDir.rename(plan.backupDir.path);
  await plan.stagingDir.rename(plan.installDir.path);
}

Future<void> _rollback(File journalFile, Object error) async {
  final journal = UpdateJournal.fromJsonString(await journalFile.readAsString());
  final plan = buildUpdatePlan(journal);
  if (!await plan.installDir.exists() && await plan.backupDir.exists()) {
    await plan.backupDir.rename(plan.installDir.path);
  }
  await journalFile.writeAsString(
    journal
        .copyWith(state: UpdateJournalState.failed, error: error.toString())
        .toJsonString(),
  );
}

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
