import 'package:flutter/material.dart';

class ExpandableOverviewSection extends StatefulWidget {
  const ExpandableOverviewSection({
    super.key,
    required this.overview,
    this.title = '剧情简介',
    this.collapsedMaxLines = 4,
    this.emptyMessage = '暂时还没有这部作品的简介。',
  });

  final String overview;
  final String title;
  final int collapsedMaxLines;
  final String emptyMessage;

  @override
  State<ExpandableOverviewSection> createState() =>
      _ExpandableOverviewSectionState();
}

class _ExpandableOverviewSectionState extends State<ExpandableOverviewSection> {
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant ExpandableOverviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overview != widget.overview) {
      _isExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = widget.overview.trim();
    final theme = Theme.of(context);

    if (overview.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(widget.emptyMessage, style: theme.textTheme.bodyLarge),
        ],
      );
    }

    final textStyle = theme.textTheme.bodyLarge;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasOverflow = _textHasOverflow(
          context: context,
          text: overview,
          style: textStyle,
          maxWidth: constraints.maxWidth,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Text(
                overview,
                maxLines: _isExpanded ? null : widget.collapsedMaxLines,
                overflow: _isExpanded
                    ? TextOverflow.visible
                    : TextOverflow.fade,
                style: textStyle,
              ),
            ),
            if (hasOverflow || _isExpanded) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Text(_isExpanded ? '收起' : '展开'),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _textHasOverflow({
    required BuildContext context,
    required String text,
    required TextStyle? style,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: widget.collapsedMaxLines,
    )..layout(maxWidth: maxWidth);

    return painter.didExceedMaxLines;
  }
}
