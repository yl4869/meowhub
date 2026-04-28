import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 当前运行环境的动态能力快照。
///
/// 这些值来自 UI 环境（MediaQuery）与 Flutter 平台信息，
/// 用于在静态解码能力之外补充“当前设备实际适合协商到什么程度”。
class CapabilitySnapshot {
  static const int _unrestrictedNativeMaxVideoWidth = 7680;
  static const int _unrestrictedNativeMaxVideoHeight = 4320;
  static const int _unrestrictedNativeMaxStreamingBitrate = 1000 * 1000 * 1000;

  const CapabilitySnapshot({
    required this.platformLabel,
    required this.targetPlatform,
    required this.isWeb,
    required this.logicalScreenSize,
    required this.physicalScreenSize,
    required this.devicePixelRatio,
    required this.orientation,
    required this.maxVideoWidth,
    required this.maxVideoHeight,
    required this.maxStreamingBitrate,
  });

  final String platformLabel;
  final TargetPlatform targetPlatform;
  final bool isWeb;
  final Size logicalScreenSize;
  final Size physicalScreenSize;
  final double devicePixelRatio;
  final Orientation orientation;
  final int maxVideoWidth;
  final int maxVideoHeight;
  final int maxStreamingBitrate;

  bool get isDesktopClass {
    if (isWeb) {
      return logicalScreenSize.shortestSide >= 900;
    }
    return switch (targetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };
  }

  bool get isMobileClass => !isDesktopClass;

  CapabilitySnapshot copyWith({
    String? platformLabel,
    TargetPlatform? targetPlatform,
    bool? isWeb,
    Size? logicalScreenSize,
    Size? physicalScreenSize,
    double? devicePixelRatio,
    Orientation? orientation,
    int? maxVideoWidth,
    int? maxVideoHeight,
    int? maxStreamingBitrate,
  }) {
    return CapabilitySnapshot(
      platformLabel: platformLabel ?? this.platformLabel,
      targetPlatform: targetPlatform ?? this.targetPlatform,
      isWeb: isWeb ?? this.isWeb,
      logicalScreenSize: logicalScreenSize ?? this.logicalScreenSize,
      physicalScreenSize: physicalScreenSize ?? this.physicalScreenSize,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
      orientation: orientation ?? this.orientation,
      maxVideoWidth: maxVideoWidth ?? this.maxVideoWidth,
      maxVideoHeight: maxVideoHeight ?? this.maxVideoHeight,
      maxStreamingBitrate: maxStreamingBitrate ?? this.maxStreamingBitrate,
    );
  }

  CapabilitySnapshot limitBitrate(int? requestedBitrate) {
    if (requestedBitrate == null || requestedBitrate <= 0) {
      return this;
    }
    final effectiveBitrate = requestedBitrate < maxStreamingBitrate
        ? requestedBitrate
        : maxStreamingBitrate;
    if (effectiveBitrate == maxStreamingBitrate) {
      return this;
    }
    return copyWith(maxStreamingBitrate: effectiveBitrate);
  }

  static CapabilitySnapshot fallback() {
    final targetPlatform = defaultTargetPlatform;
    final isDesktopClass = switch (targetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };
    final defaultSize = isDesktopClass
        ? const Size(1440, 900)
        : const Size(390, 844);
    return fromInputs(
      logicalSize: defaultSize,
      devicePixelRatio: 2,
      orientation: defaultSize.width > defaultSize.height
          ? Orientation.landscape
          : Orientation.portrait,
      targetPlatform: targetPlatform,
      isWeb: kIsWeb,
    );
  }

  static CapabilitySnapshot fromContext(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return fromInputs(
      logicalSize: mediaQuery.size,
      devicePixelRatio: mediaQuery.devicePixelRatio,
      orientation: mediaQuery.orientation,
      targetPlatform: defaultTargetPlatform,
      isWeb: kIsWeb,
    );
  }

  static CapabilitySnapshot fromInputs({
    required Size logicalSize,
    required double devicePixelRatio,
    required Orientation orientation,
    required TargetPlatform targetPlatform,
    required bool isWeb,
  }) {
    final normalizedDpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final physicalSize = Size(
      logicalSize.width * normalizedDpr,
      logicalSize.height * normalizedDpr,
    );
    if (!isWeb) {
      return CapabilitySnapshot(
        platformLabel: _platformLabel(
          targetPlatform: targetPlatform,
          isWeb: isWeb,
        ),
        targetPlatform: targetPlatform,
        isWeb: isWeb,
        logicalScreenSize: logicalSize,
        physicalScreenSize: physicalSize,
        devicePixelRatio: normalizedDpr,
        orientation: orientation,
        // 原生端交给本地播放器自行下采样，不再按屏幕尺寸限制协商上限。
        maxVideoWidth: _unrestrictedNativeMaxVideoWidth,
        maxVideoHeight: _unrestrictedNativeMaxVideoHeight,
        maxStreamingBitrate: _unrestrictedNativeMaxStreamingBitrate,
      );
    }
    final videoTier = _resolveVideoTier(
      longestPhysicalEdgePx: physicalSize.longestSide.round(),
      shortestPhysicalEdgePx: physicalSize.shortestSide.round(),
      isWeb: isWeb,
      targetPlatform: targetPlatform,
    );
    final estimatedBitrate = _estimateMaxStreamingBitrate(
      maxVideoWidth: videoTier.width,
      isWeb: isWeb,
      targetPlatform: targetPlatform,
    );

    return CapabilitySnapshot(
      platformLabel: _platformLabel(
        targetPlatform: targetPlatform,
        isWeb: isWeb,
      ),
      targetPlatform: targetPlatform,
      isWeb: isWeb,
      logicalScreenSize: logicalSize,
      physicalScreenSize: physicalSize,
      devicePixelRatio: normalizedDpr,
      orientation: orientation,
      maxVideoWidth: videoTier.width,
      maxVideoHeight: videoTier.height,
      maxStreamingBitrate: estimatedBitrate,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CapabilitySnapshot &&
        other.platformLabel == platformLabel &&
        other.targetPlatform == targetPlatform &&
        other.isWeb == isWeb &&
        other.logicalScreenSize == logicalScreenSize &&
        other.physicalScreenSize == physicalScreenSize &&
        other.devicePixelRatio == devicePixelRatio &&
        other.orientation == orientation &&
        other.maxVideoWidth == maxVideoWidth &&
        other.maxVideoHeight == maxVideoHeight &&
        other.maxStreamingBitrate == maxStreamingBitrate;
  }

  @override
  int get hashCode => Object.hash(
    platformLabel,
    targetPlatform,
    isWeb,
    logicalScreenSize,
    physicalScreenSize,
    devicePixelRatio,
    orientation,
    maxVideoWidth,
    maxVideoHeight,
    maxStreamingBitrate,
  );

  static _VideoTier _resolveVideoTier({
    required int longestPhysicalEdgePx,
    required int shortestPhysicalEdgePx,
    required bool isWeb,
    required TargetPlatform targetPlatform,
  }) {
    final desktopLike =
        !isWeb &&
        switch (targetPlatform) {
          TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux => true,
          TargetPlatform.android ||
          TargetPlatform.iOS ||
          TargetPlatform.fuchsia => false,
        };

    if (longestPhysicalEdgePx >= 3200 && shortestPhysicalEdgePx >= 1800) {
      return const _VideoTier(3840, 2160);
    }
    if (longestPhysicalEdgePx >= 2200 && shortestPhysicalEdgePx >= 1200) {
      return const _VideoTier(2560, 1440);
    }
    if (longestPhysicalEdgePx >= 1700 && shortestPhysicalEdgePx >= 900) {
      return const _VideoTier(1920, 1080);
    }
    if (desktopLike && longestPhysicalEdgePx >= 1400) {
      return const _VideoTier(1920, 1080);
    }
    if (longestPhysicalEdgePx >= 1100) {
      return const _VideoTier(1280, 720);
    }
    return const _VideoTier(854, 480);
  }

  static int _estimateMaxStreamingBitrate({
    required int maxVideoWidth,
    required bool isWeb,
    required TargetPlatform targetPlatform,
  }) {
    final baseBitrate = switch (maxVideoWidth) {
      >= 3840 => 35 * 1000 * 1000,
      >= 2560 => 20 * 1000 * 1000,
      >= 1920 => 12 * 1000 * 1000,
      >= 1280 => 6 * 1000 * 1000,
      _ => 3 * 1000 * 1000,
    };

    if (isWeb) {
      return (baseBitrate * 0.8).round();
    }

    return switch (targetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => baseBitrate,
      TargetPlatform.android => (baseBitrate * 0.85).round(),
      TargetPlatform.iOS => (baseBitrate * 0.75).round(),
      TargetPlatform.fuchsia => baseBitrate,
    };
  }

  static String _platformLabel({
    required TargetPlatform targetPlatform,
    required bool isWeb,
  }) {
    if (isWeb) {
      return 'web';
    }
    return targetPlatform.name;
  }
}

class CapabilityProber extends ChangeNotifier {
  CapabilitySnapshot _snapshot = CapabilitySnapshot.fallback();

  CapabilitySnapshot get snapshot => _snapshot;

  void probe(BuildContext context) {
    final nextSnapshot = CapabilitySnapshot.fromContext(context);
    if (nextSnapshot == _snapshot) {
      return;
    }
    _snapshot = nextSnapshot;
    notifyListeners();
  }
}

/// 根部探测器：监听 MediaQuery/窗口变化，并把能力快照同步进 `CapabilityProber`。
class CapabilityProbeHost extends StatefulWidget {
  const CapabilityProbeHost({super.key, required this.child});

  final Widget child;

  @override
  State<CapabilityProbeHost> createState() => _CapabilityProbeHostState();
}

class _CapabilityProbeHostState extends State<CapabilityProbeHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleProbe();
  }

  @override
  void didChangeMetrics() {
    _scheduleProbe();
  }

  void _scheduleProbe() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<CapabilityProber>().probe(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _VideoTier {
  const _VideoTier(this.width, this.height);

  final int width;
  final int height;
}
