import 'package:flutter/material.dart';

typedef ResponsivePageBuilder =
    Widget Function(BuildContext context, double maxWidth);

class AppResponsiveBreakpoints {
  AppResponsiveBreakpoints._();

  static const double tablet = 720;

  static bool isTabletWidth(double width) => width >= tablet;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (AppResponsiveBreakpoints.isTabletWidth(maxWidth)) {
          return tabletBuilder(context, maxWidth);
        }
        return mobileBuilder(context, maxWidth);
      },
    );
  }
}
