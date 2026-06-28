import '../models/manifest_model.dart';

enum UpdateStrategy {
  inPlace,
  installer,
  copyLink,
}

class WindowsUpdateCapabilities {
  final bool isWindows;
  final bool installDirWritable;
  final String? failedInPlaceVersion;

  const WindowsUpdateCapabilities({
    required this.isWindows,
    required this.installDirWritable,
    this.failedInPlaceVersion,
  });
}

UpdateStrategy decideWindowsUpdateStrategy({
  required PlatformRelease release,
  required WindowsUpdateCapabilities capabilities,
}) {
  if (!capabilities.isWindows || release.type.toLowerCase() != 'native') {
    return UpdateStrategy.copyLink;
  }

  final canUseInstaller = release.url.isNotEmpty &&
      (release.sha256.isNotEmpty || release.md5.isNotEmpty);
  final hasFailedThisVersion =
      capabilities.failedInPlaceVersion == release.version;

  final package = release.package;
  if (!hasFailedThisVersion &&
      capabilities.installDirWritable &&
      package != null &&
      package.enabled &&
      package.url.isNotEmpty &&
      package.sha256.isNotEmpty) {
    return UpdateStrategy.inPlace;
  }

  if (canUseInstaller) {
    return UpdateStrategy.installer;
  }

  return UpdateStrategy.copyLink;
}
