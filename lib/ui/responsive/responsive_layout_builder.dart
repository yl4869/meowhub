import 'package:flutter/material.dart';

typedef ResponsivePageBuilder =
    Widget Function(BuildContext context, double maxWidth);

class AppResponsiveBreakpoints {
  AppResponsiveBreakpoints._();

  static const double tablet = 720;

  static bool isTabletWidth(double width) => width >= tablet;
}

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobileBuilder,
    required this.tabletBuilder,
  });

  final ResponsivePageBuilder mobileBuilder;
  final ResponsivePageBuilder tabletBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isTablet = AppResponsiveBreakpoints.isTabletWidth(maxWidth);

        return IndexedStack(
          index: isTablet ? 1 : 0,
          sizing: StackFit.expand,
          children: [
            KeyedSubtree(
              key: const ValueKey('responsive-mobile'),
              child: TickerMode(
                enabled: !isTablet,
                child: mobileBuilder(context, maxWidth),
              ),
            ),
            KeyedSubtree(
              key: const ValueKey('responsive-tablet'),
              child: TickerMode(
                enabled: isTablet,
                child: tabletBuilder(context, maxWidth),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ResponsiveLayoutBuilder extends StatelessWidget {
  const ResponsiveLayoutBuilder({
    super.key,
    required this.mobileBuilder,
    required this.tabletBuilder,
  });

  final ResponsivePageBuilder mobileBuilder;
  final ResponsivePageBuilder tabletBuilder;

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileBuilder: mobileBuilder,
      tabletBuilder: tabletBuilder,
    );
  }
}
