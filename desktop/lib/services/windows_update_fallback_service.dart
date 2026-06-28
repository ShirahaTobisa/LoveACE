import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class WindowsUpdateFallbackService {
  WindowsUpdateFallbackService._();

  static const _failedInPlaceVersionKey =
      'windows_update_failed_in_place_version';

  static Future<String?> failedInPlaceVersion() async {
    if (!Platform.isWindows) return null;
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString(_failedInPlaceVersionKey);
    return version?.isNotEmpty == true ? version : null;
  }

  static Future<void> markInPlaceFailed(String version) async {
    if (!Platform.isWindows || version.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_failedInPlaceVersionKey, version);
  }

  static Future<void> clearInPlaceFailure() async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedInPlaceVersionKey);
  }
}
