import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_journal.dart';

class UpdatePlan {
  final Directory installDir;
  final Directory stagingDir;
  final Directory backupDir;
  final File newExecutable;

  const UpdatePlan({
    required this.installDir,
    required this.stagingDir,
    required this.backupDir,
    required this.newExecutable,
  });
}

UpdatePlan buildUpdatePlan(UpdateJournal journal) {
  final installDir = Directory(journal.installDir);
  final stagingDir = Directory(journal.stagingDir);
  final backupDir = Directory(journal.backupDir);
  return UpdatePlan(
    installDir: installDir,
    stagingDir: stagingDir,
    backupDir: backupDir,
    newExecutable: File(p.join(stagingDir.path, 'loveace.exe')),
  );
}

Future<void> validatePlan(UpdatePlan plan) async {
  if (!await plan.installDir.exists()) {
    throw StateError('install_dir does not exist: ${plan.installDir.path}');
  }
  if (!await plan.stagingDir.exists()) {
    throw StateError('staging_dir does not exist: ${plan.stagingDir.path}');
  }
  if (!await plan.newExecutable.exists() || await plan.newExecutable.length() <= 0) {
    throw StateError('staging loveace.exe is missing or empty');
  }
  final installParent = p.normalize(plan.installDir.parent.absolute.path).toLowerCase();
  final stagingParent = p.normalize(plan.stagingDir.parent.absolute.path).toLowerCase();
  final backupParent = p.normalize(plan.backupDir.parent.absolute.path).toLowerCase();
  if (stagingParent != installParent || backupParent != installParent) {
    throw StateError('staging_dir and backup_dir must be siblings of install_dir');
  }
}
