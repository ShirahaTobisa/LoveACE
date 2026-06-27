import 'dart:convert';

enum WindowsUpdateJournalState {
  pending,
  done,
  failed,
}

class WindowsUpdateJournal {
  final String fromVersion;
  final String toVersion;
  final String installDir;
  final String stagingDir;
  final String backupDir;
  final WindowsUpdateJournalState state;
  final String? error;

  const WindowsUpdateJournal({
    required this.fromVersion,
    required this.toVersion,
    required this.installDir,
    required this.stagingDir,
    required this.backupDir,
    required this.state,
    this.error,
  });

  WindowsUpdateJournal copyWith({
    WindowsUpdateJournalState? state,
    String? error,
  }) {
    return WindowsUpdateJournal(
      fromVersion: fromVersion,
      toVersion: toVersion,
      installDir: installDir,
      stagingDir: stagingDir,
      backupDir: backupDir,
      state: state ?? this.state,
      error: error ?? this.error,
    );
  }

  factory WindowsUpdateJournal.fromJson(Map<String, dynamic> json) {
    return WindowsUpdateJournal(
      fromVersion: json['from'] as String? ?? '',
      toVersion: json['to'] as String? ?? '',
      installDir: json['install_dir'] as String? ?? '',
      stagingDir: json['staging_dir'] as String? ?? '',
      backupDir: json['backup_dir'] as String? ?? '',
      state: _stateFromString(json['state'] as String? ?? 'pending'),
      error: json['error'] as String?,
    );
  }

  factory WindowsUpdateJournal.fromJsonString(String source) {
    return WindowsUpdateJournal.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
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

  static WindowsUpdateJournalState _stateFromString(String value) {
    return WindowsUpdateJournalState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => WindowsUpdateJournalState.pending,
    );
  }
}
