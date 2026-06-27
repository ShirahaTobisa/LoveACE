import 'dart:convert';

enum UpdateJournalState {
  pending,
  done,
  failed,
}

class UpdateJournal {
  final String fromVersion;
  final String toVersion;
  final String installDir;
  final String stagingDir;
  final String backupDir;
  final UpdateJournalState state;
  final String? error;

  const UpdateJournal({
    required this.fromVersion,
    required this.toVersion,
    required this.installDir,
    required this.stagingDir,
    required this.backupDir,
    required this.state,
    this.error,
  });

  factory UpdateJournal.fromJson(Map<String, dynamic> json) {
    return UpdateJournal(
      fromVersion: json['from'] as String? ?? '',
      toVersion: json['to'] as String? ?? '',
      installDir: json['install_dir'] as String? ?? '',
      stagingDir: json['staging_dir'] as String? ?? '',
      backupDir: json['backup_dir'] as String? ?? '',
      state: _stateFromString(json['state'] as String? ?? 'pending'),
      error: json['error'] as String?,
    );
  }

  factory UpdateJournal.fromJsonString(String source) {
    return UpdateJournal.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  UpdateJournal copyWith({
    UpdateJournalState? state,
    String? error,
  }) {
    return UpdateJournal(
      fromVersion: fromVersion,
      toVersion: toVersion,
      installDir: installDir,
      stagingDir: stagingDir,
      backupDir: backupDir,
      state: state ?? this.state,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'from': fromVersion,
      'to': toVersion,
      'install_dir': installDir,
      'staging_dir': stagingDir,
      'backup_dir': backupDir,
      'state': state.name,
      if (error != null) 'error': error,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static UpdateJournalState _stateFromString(String value) {
    return UpdateJournalState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => UpdateJournalState.pending,
    );
  }
}
