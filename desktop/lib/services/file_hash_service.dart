import 'dart:io';

import 'package:crypto/crypto.dart';

class FileHashService {
  FileHashService._();

  static Future<String> md5Hex(File file) async {
    final digest = await md5.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<String> sha256Hex(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
