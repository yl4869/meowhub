import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.url,
    this.fit,
    this.width,
    this.height,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('file://')) {
      final filePath = Uri.parse(url).toFilePath();
      final file = File(filePath);
      if (!file.existsSync()) {
        return const _Fallback();
      }
      return Image.file(
        file,
        fit: fit ?? BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (_, _2, _3) => const _Fallback(),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit ?? BoxFit.cover,
      width: width,
      height: height,
      placeholder: (_, _2) => const _Shimmer(),
      errorWidget: (_, _2, _3) => const _Fallback(),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          color: Colors.white.withValues(alpha: 0.2),
          size: 32,
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer();

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.white.withValues(alpha: 0.05));
  }
}
