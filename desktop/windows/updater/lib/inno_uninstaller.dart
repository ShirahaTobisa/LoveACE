import 'dart:io';

class InnoUninstallerCopyResult {
  final int copiedCount;

  const InnoUninstallerCopyResult(this.copiedCount);

  bool get foundFiles => copiedCount > 0;
}

Future<InnoUninstallerCopyResult> copyInnoUninstallerFiles({
  required Directory from,
  required Directory to,
}) async {
  if (!await from.exists()) {
    return const InnoUninstallerCopyResult(0);
  }

  await to.create(recursive: true);
  var copiedCount = 0;
  await for (final entity in from.list(followLinks: false)) {
    if (entity is! File) continue;

    final name = entity.uri.pathSegments.last.toLowerCase();
    if (!_isInnoUninstallerFile(name)) continue;

    await entity.copy(
      '${to.path}${Platform.pathSeparator}${entity.uri.pathSegments.last}',
    );
    copiedCount++;
  }

  return InnoUninstallerCopyResult(copiedCount);
}

bool _isInnoUninstallerFile(String lowerName) {
  return lowerName.startsWith('unins') &&
      (lowerName.endsWith('.exe') || lowerName.endsWith('.dat'));
}
