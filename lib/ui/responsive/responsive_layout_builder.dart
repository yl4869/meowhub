import 'package:flutter/material.dart';

typedef ResponsivePageBuilder =
    Widget Function(BuildContext context, double maxWidth);

enum ResponsiveLayoutType { mobile, tablet }

class ResponsiveLayoutContext {
  const ResponsiveLayoutContext({
    required this.maxWidth,
    required this.layoutType,
  });

  final double maxWidth;
  final ResponsiveLayoutType layoutType;

  bool get isTablet => layoutType == ResponsiveLayoutType.tablet;
  bool get isMobile => layoutType == ResponsiveLayoutType.mobile;
}

class AppResponsiveBreakpoints {
  AppResponsiveBreakpoints._();

  static const double tablet = 720;

  static bool isTabletShortestSide(double shortestSide) =>
      shortestSide >= tablet;
}

/// Refactor reason:
/// A single responsive entry point standardizes breakpoint decisions so pages
/// no longer duplicate mobile/tablet branching logic.
class ResponsiveLayoutBuilder extends StatelessWidget {
  const ResponsiveLayoutBuilder({
    super.key,
    required this.mobileBuilder,
    required this.tabletBuilder,
    this.builder,
  });

  final ResponsivePageBuilder mobileBuilder;
  final ResponsivePageBuilder tabletBuilder;
  final Widget Function(BuildContext context, ResponsiveLayoutContext layout)?
  builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final isTablet = AppResponsiveBreakpoints.isTabletShortestSide(
          shortestSide,
        );
        final layout = ResponsiveLayoutContext(
          maxWidth: maxWidth,
          layoutType: isTablet
              ? ResponsiveLayoutType.tablet
              : ResponsiveLayoutType.mobile,
        );

        if (builder != null) {
          return builder!(context, layout);
        }

        // 重要：仅构建当前布局对应的子树，避免两个播放器页面同时实例化
        if (isTablet) {
          return KeyedSubtree(
            key: const ValueKey('responsive-tablet'),
            child: tabletBuilder(context, maxWidth),
          );
        } else {
          return KeyedSubtree(
            key: const ValueKey('responsive-mobile'),
            child: mobileBuilder(context, maxWidth),
          );
        }
      },
    );
  }
}
