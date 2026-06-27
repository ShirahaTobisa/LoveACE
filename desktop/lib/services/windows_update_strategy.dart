import '../models/manifest_model.dart';

enum UpdateStrategy {
  inPlace,
  installer,
  copyLink,
}

class WindowsUpdateCapabilities {
  final bool isWindows;
  final bool installDirWritable;

  const WindowsUpdateCapabilities({
    required this.isWindows,
    required this.installDirWritable,
  });
}

UpdateStrategy decideWindowsUpdateStrategy({
  required PlatformRelease release,
  required WindowsUpdateCapabilities capabilities,
}) {
  if (!capabilities.isWindows || release.type.toLowerCase() != 'native') {
    return UpdateStrategy.copyLink;
  }

  final package = release.package;
  if (capabilities.installDirWritable &&
      package != null &&
      package.enabled &&
      package.url.isNotEmpty &&
      package.sha256.isNotEmpty) {
    return UpdateStrategy.inPlace;
  }

  if (release.url.isNotEmpty &&
      (release.sha256.isNotEmpty || release.md5.isNotEmpty)) {
    return UpdateStrategy.installer;
  }

  return UpdateStrategy.copyLink;
}
