import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/media_item.dart';
import '../../theme/app_theme.dart';

class CastListSection extends StatelessWidget {
  const CastListSection({
    super.key,
    required this.cast,
    this.onViewAll,
    this.onCastTap,
  });

  final List<Cast> cast;
  final VoidCallback? onViewAll;
  final ValueChanged<Cast>? onCastTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('演职员', style: Theme.of(context).textTheme.titleLarge),
            ),
            TextButton.icon(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 154,
          child: cast.isEmpty
              ? const _CastEmptyState()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: cast.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final castMember = cast[index];
                    return _CastCard(
                      castMember: castMember,
                      onTap: onCastTap == null
                          ? null
                          : () => onCastTap!(castMember),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.castMember, this.onTap});

  final Cast castMember;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 90,
                  height: 90,
                  child: castMember.avatarUrl.isEmpty
                      ? const ColoredBox(
                          color: AppTheme.backgroundColor,
                          child: Icon(
                            Icons.person_rounded,
                            color: Colors.white38,
                            size: 28,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: castMember.avatarUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              const ColoredBox(
                                color: AppTheme.backgroundColor,
                                child: Icon(
                                  Icons.person_rounded,
                                  color: Colors.white38,
                                  size: 28,
                                ),
                              ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                castMember.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                castMember.characterName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CastEmptyState extends StatelessWidget {
  const _CastEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('暂无演职员信息', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
