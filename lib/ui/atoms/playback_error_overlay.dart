import 'package:flutter/material.dart';

class PlaybackErrorOverlay extends StatelessWidget {
  const PlaybackErrorOverlay({
    super.key,
    required this.message,
    required this.isRetrying,
    required this.hasRetry,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final bool isRetrying;
  final bool hasRetry;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.white.withValues(alpha: 0.6),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                '播放出错',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: onDismiss,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: const Text('关闭'),
                  ),
                  if (hasRetry) ...[
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: isRetrying ? null : onRetry,
                      child: isRetrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('转码重试'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
