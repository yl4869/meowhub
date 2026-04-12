import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../models/media_item.dart';
import '../../theme/app_theme.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.mediaItem,
    this.onTap,
    this.isFavorite = false,
    this.isRecent = false,
    this.progress = 0,
  });

  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool isFavorite;
  final bool isRecent;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();

    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPosterImage(),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _RatingBadge(rating: mediaItem.rating),
                ),
                if (isRecent)
                  const Positioned(top: 10, left: 10, child: _RecentBadge()),
                if (isFavorite)
                  Positioned(
                    top: 42,
                    left: 10,
                    child: const _FavoriteBadge(),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _TitleOverlay(title: mediaItem.title),
                ),
                if (normalizedProgress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ProgressIndicatorBar(progress: normalizedProgress),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterImage() {
    final posterUrl = mediaItem.posterUrl;

    if (posterUrl == null || posterUrl.isEmpty) {
      return const _PosterFallback();
    }

    return CachedNetworkImage(
      imageUrl: posterUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => const _PosterShimmer(),
      errorWidget: (context, url, error) => const _PosterFallback(),
    );
  }
}

class _FavoriteBadge extends StatelessWidget {
  const _FavoriteBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(
          Icons.favorite_rounded,
          size: 14,
          color: AppTheme.accentColor,
        ),
      ),
    );
  }
}

class _RecentBadge extends StatelessWidget {
  const _RecentBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.accentColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '最近观看',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 11,
            color: AppTheme.onAccentColor,
          ),
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          rating > 0 ? rating.toStringAsFixed(1) : '--',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 12,
            color: Colors.white,
            shadows: const [
              Shadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressIndicatorBar extends StatelessWidget {
  const _ProgressIndicatorBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black.withValues(alpha: 0.35)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: const ColoredBox(color: AppTheme.accentColor),
          ),
        ],
      ),
    );
  }
}

class _TitleOverlay extends StatelessWidget {
  const _TitleOverlay({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.82),
          ],
        ),
      ),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

class _PosterShimmer extends StatelessWidget {
  const _PosterShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF202020),
      highlightColor: const Color(0xFF2C2C2C),
      child: const DecoratedBox(
        decoration: BoxDecoration(color: AppTheme.cardColor),
        child: Center(
          child: Icon(
            Icons.movie_creation_outlined,
            size: 34,
            color: Colors.white24,
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.cardColor,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        size: 40,
        color: Colors.white.withValues(alpha: 0.5),
      ),
    );
  }
}
