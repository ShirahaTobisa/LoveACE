import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../../models/manifest_model.dart';
import '../../services/analytics_service.dart';
import '../../services/logger_service.dart';
import '../../services/windows_update_fallback_service.dart';
import '../../services/windows_update_service.dart';
import '../../services/windows_update_strategy.dart';

/// WinUI 风格的 OTA 更新对话框
///
/// 使用 fluent_ui 的 ContentDialog 显示更新信息
/// 支持强制更新和可选更新
class WinUIOTADialog extends StatefulWidget {
  final OTA ota;
  final String currentVersion;
  final String platform;
  final VoidCallback? onDismiss;

  const WinUIOTADialog({
    super.key,
    required this.ota,
    required this.currentVersion,
    required this.platform,
    this.onDismiss,
  });

  @override
  State<WinUIOTADialog> createState() => _WinUIOTADialogState();

  /// 显示 OTA 更新对话框
  static Future<void> show(
    BuildContext context, {
    required OTA ota,
    required String currentVersion,
    required String platform,
    VoidCallback? onDismiss,
  }) {
    final release = ota.getPlatformRelease(platform);
    final isForceUpdate = release?.forceOta ?? false;

    return showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => WinUIOTADialog(
        ota: ota,
        currentVersion: currentVersion,
        platform: platform,
        onDismiss: onDismiss,
      ),
    );
  }
}

class _WinUIOTADialogState extends State<WinUIOTADialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _installDirWritable = false;
  String? _failedInPlaceVersion;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    final writable = await WindowsUpdateService.isInstallDirectoryWritable();
    final failedInPlaceVersion =
        await WindowsUpdateFallbackService.failedInPlaceVersion();
    final release = widget.ota.getPlatformRelease(widget.platform);
    final effectiveFailedInPlaceVersion =
        failedInPlaceVersion != null && failedInPlaceVersion != release?.version
            ? null
            : failedInPlaceVersion;
    if (failedInPlaceVersion != null &&
        effectiveFailedInPlaceVersion == null) {
      await WindowsUpdateFallbackService.clearInPlaceFailure();
    }
    if (!mounted) return;
    setState(() {
      _installDirWritable = writable;
      _failedInPlaceVersion = effectiveFailedInPlaceVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.ota.getPlatformRelease(widget.platform);
    if (release == null) {
      return const SizedBox.shrink();
    }

    final isForceUpdate = release.forceOta;
    final theme = FluentTheme.of(context);
    final strategy = decideWindowsUpdateStrategy(
      release: release,
      capabilities: WindowsUpdateCapabilities(
        isWindows: WindowsUpdateService.isSupported,
        installDirWritable: _installDirWritable,
        failedInPlaceVersion: _failedInPlaceVersion,
      ),
    );
    final usingInstallerFallback =
        strategy == UpdateStrategy.installer &&
        _failedInPlaceVersion == release.version;

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.sync,
              color: theme.accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('发现新版本'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVersionInfo(context, theme, release.version),
            const SizedBox(height: 20),
            if (widget.ota.content.isNotEmpty) ...[
              _buildSectionTitle(theme, '更新内容'),
              const SizedBox(height: 10),
              _buildContentBox(theme, widget.ota.content),
              const SizedBox(height: 20),
            ],
            if (widget.ota.notice.isNotEmpty) ...[
              InfoBar(
                title: const Text('更新提示'),
                content: Text(widget.ota.notice),
                severity: InfoBarSeverity.warning,
                isLong: true,
              ),
              const SizedBox(height: 20),
            ],
            if (widget.ota.changelog.isNotEmpty) ...[
              _buildSectionTitle(theme, '更新日志'),
              const SizedBox(height: 10),
              _buildChangelogBox(context, theme),
              const SizedBox(height: 20),
            ],
            _buildSectionTitle(theme, '下载链接'),
            const SizedBox(height: 10),
            _buildDownloadLinkBox(context, theme, release.url, strategy),
            const SizedBox(height: 20),
            if (usingInstallerFallback) ...[
              _buildInstallerFallbackNotice(),
              const SizedBox(height: 20),
            ],
            if (release.sha256.isNotEmpty)
              _buildHashBox(theme, 'SHA256 校验值', release.sha256)
            else if (release.md5.isNotEmpty)
              _buildHashBox(theme, 'MD5 校验值', release.md5),
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              _buildDownloadProgress(theme),
            ],
            if (isForceUpdate) ...[
              const SizedBox(height: 20),
              _buildForceUpdateWarning(),
            ],
          ],
        ),
      ),
      actions: [
        if (!isForceUpdate)
          Button(
            onPressed: _isDownloading ? null : () {
              Navigator.pop(context);
              widget.onDismiss?.call();
            },
            child: const Text('稍后更新'),
          ),
        FilledButton(
          onPressed: _isDownloading
              ? null
              : () {
                  AnalyticsService.instance.trackOtaUpdateClick(
                    widget.currentVersion,
                    release.version,
                  );
                  _runUpdateAction(context, release, strategy);
                },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _actionIcon(strategy),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(_actionLabel(strategy)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVersionInfo(
      BuildContext context, FluentThemeData theme, String newVersion) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前版本',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.currentVersion,
                  style: theme.typography.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              FluentIcons.forward,
              color: Colors.green,
              size: 16,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '新版本',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  newVersion,
                  style: theme.typography.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(FluentThemeData theme, String title) {
    return Text(
      title,
      style: theme.typography.bodyStrong,
    );
  }

  Widget _buildContentBox(FluentThemeData theme, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
      ),
      child: Text(
        content,
        style: theme.typography.body?.copyWith(height: 1.6),
      ),
    );
  }

  Widget _buildChangelogBox(BuildContext context, FluentThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.ota.changelog.take(3).map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'v${entry.version}',
                  style: theme.typography.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.changes,
                  style: theme.typography.caption?.copyWith(height: 1.5),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDownloadLinkBox(
    BuildContext context,
    FluentThemeData theme,
    String url,
    UpdateStrategy strategy,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            url,
            style: theme.typography.caption?.copyWith(
              fontFamily: 'monospace',
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _downloadHelpText(strategy),
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHashBox(FluentThemeData theme, String title, String hash) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            hash,
            style: theme.typography.caption?.copyWith(
              fontFamily: 'monospace',
              color: theme.inactiveColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForceUpdateWarning() {
    return InfoBar(
      title: const Text('强制更新'),
      content: const Text('此版本为强制更新，您必须更新才能继续使用应用'),
      severity: InfoBarSeverity.warning,
      isLong: true,
    );
  }

  Widget _buildInstallerFallbackNotice() {
    return const InfoBar(
      title: Text('改用安装器更新'),
      content: Text('上次内部替换更新未完成，本次将下载安装器并启动安装流程。'),
      severity: InfoBarSeverity.warning,
      isLong: true,
    );
  }

  Widget _buildDownloadProgress(FluentThemeData theme) {
    final percent = (_downloadProgress * 100).clamp(0, 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('正在下载更新', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        ProgressBar(value: percent.toDouble()),
        const SizedBox(height: 6),
        Text(
          '$percent%',
          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
        ),
      ],
    );
  }

  Future<void> _downloadAndLaunchInstaller(
    BuildContext context,
    PlatformRelease release,
  ) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final result = await WindowsUpdateService.downloadInstaller(
        release: release,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _downloadProgress = (received / total).clamp(0, 1).toDouble();
          });
        },
      );

      if (!mounted || !context.mounted) return;
      setState(() => _downloadProgress = 1);

      await WindowsUpdateService.launchInstaller(result.installer);

      if (!mounted || !context.mounted) return;
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('安装器已启动'),
          content: const Text('请按安装器提示完成更新，安装时可能需要关闭当前应用。'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
        duration: const Duration(seconds: 5),
      );
      Navigator.pop(context);
    } catch (e) {
      LoggerService.error('❌ Windows 更新失败', error: e);
      if (!mounted || !context.mounted) return;
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('更新失败'),
          content: Text(e.toString()),
          severity: InfoBarSeverity.error,
          isLong: true,
          onClose: close,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _runUpdateAction(
    BuildContext context,
    PlatformRelease release,
    UpdateStrategy strategy,
  ) {
    switch (strategy) {
      case UpdateStrategy.inPlace:
        _downloadAndLaunchHelper(context, release);
        return;
      case UpdateStrategy.installer:
        _downloadAndLaunchInstaller(context, release);
        return;
      case UpdateStrategy.copyLink:
        _copyToClipboard(context, release.url);
        return;
    }
  }

  Future<void> _downloadAndLaunchHelper(
    BuildContext context,
    PlatformRelease release,
  ) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final result = await WindowsUpdateService.prepareInPlacePackage(
        release: release,
        currentVersion: widget.currentVersion,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _downloadProgress = (received / total).clamp(0, 1).toDouble();
          });
        },
      );

      if (!mounted || !context.mounted) return;
      setState(() => _downloadProgress = 1);

      await WindowsUpdateService.launchHelper(result.journalFile);

      if (!mounted || !context.mounted) return;
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('更新准备完成'),
          content: const Text('应用即将关闭并完成替换，随后会自动重启。'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
        duration: const Duration(seconds: 3),
      );
      Navigator.pop(context);
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 500),
          () => exit(0),
        ),
      );
    } catch (e) {
      LoggerService.error('❌ Windows 内部更新失败', error: e);
      if (!mounted || !context.mounted) return;
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('内部更新失败'),
          content: Text('$e\n请稍后重试，或使用安装器链接手动更新。'),
          severity: InfoBarSeverity.error,
          isLong: true,
          onClose: close,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  IconData _actionIcon(UpdateStrategy strategy) {
    return switch (strategy) {
      UpdateStrategy.inPlace => FluentIcons.sync,
      UpdateStrategy.installer => FluentIcons.download,
      UpdateStrategy.copyLink => FluentIcons.copy,
    };
  }

  String _actionLabel(UpdateStrategy strategy) {
    return switch (strategy) {
      UpdateStrategy.inPlace => '立即更新',
      UpdateStrategy.installer => '下载并安装',
      UpdateStrategy.copyLink => '复制链接',
    };
  }

  String _downloadHelpText(UpdateStrategy strategy) {
    return switch (strategy) {
      UpdateStrategy.inPlace => '点击下方按钮后，应用会下载并校验更新包，然后关闭并重启。',
      UpdateStrategy.installer => '点击下方按钮后，应用会下载并校验安装器。',
      UpdateStrategy.copyLink => '选择复制，或点击下方按钮复制后在浏览器打开',
    };
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    LoggerService.info('📋 已复制下载链接');

    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('已复制'),
          content: const Text('下载链接已复制，请在浏览器中打开下载'),
          severity: InfoBarSeverity.success,
          onClose: close,
        );
      },
      duration: const Duration(seconds: 3),
    );
  }

}
