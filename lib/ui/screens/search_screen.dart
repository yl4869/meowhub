import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/repositories/i_media_repository.dart';
import '../../providers/media_library_provider.dart';
import '../../theme/app_theme.dart';
import '../atoms/app_surface_card.dart';
import '../atoms/poster_card.dart';
import '../atoms/poster_card_skeleton.dart';

class MeowSearchDelegate extends SearchDelegate<MediaItem?> {
  MeowSearchDelegate() : super(searchFieldLabel: '搜索电影、剧集...');

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: const TextStyle(color: Colors.white38),
        border: InputBorder.none,
        filled: true,
        fillColor: AppTheme.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isNotEmpty) {
      return [
        IconButton(
          icon: const Icon(Icons.clear_rounded, size: 22),
          onPressed: () => query = '',
        ),
      ];
    }
    return null;
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  static const Duration _debounceDelay = Duration(milliseconds: 300);
  static const int _minQueryLength = 2;
  static const int _localSearchMaxItems = 500;

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return _SearchEmptyState();
    }
    if (query.trim().length < _minQueryLength) {
      return const _SearchEmptyState(message: '请至少输入 2 个字符');
    }
    return _DebouncedSearchResults(
      query: query,
      onItemSelected: (item) => close(context, item),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().length < _minQueryLength) {
      return const _SearchEmptyState(message: '请至少输入 2 个字符');
    }
    return _DebouncedSearchResults(
      query: query,
      onItemSelected: (item) => close(context, item),
    );
  }
}

class _DebouncedSearchResults extends StatefulWidget {
  const _DebouncedSearchResults({
    required this.query,
    required this.onItemSelected,
  });

  final String query;
  final ValueChanged<MediaItem> onItemSelected;

  @override
  State<_DebouncedSearchResults> createState() =>
      _DebouncedSearchResultsState();
}

class _DebouncedSearchResultsState extends State<_DebouncedSearchResults> {
  Timer? _debounceTimer;
  String _debouncedQuery = '';

  @override
  void initState() {
    super.initState();
    _debouncedQuery = widget.query;
  }

  @override
  void didUpdateWidget(covariant _DebouncedSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query == _debouncedQuery) return;

    _debounceTimer?.cancel();
    if (widget.query.trim().isEmpty) {
      setState(() => _debouncedQuery = widget.query);
      return;
    }
    _debounceTimer = Timer(MeowSearchDelegate._debounceDelay, () {
      if (mounted) {
        setState(() => _debouncedQuery = widget.query);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<IMediaRepository>();
    final libraryProvider = context.read<MediaLibraryProvider>();
    final needsRefresh = ValueNotifier<int>(0);

    return ValueListenableBuilder<int>(
      valueListenable: needsRefresh,
      builder: (context, refresh, child) {
        final q = _debouncedQuery.trim();
        if (q.isEmpty || q.length < MeowSearchDelegate._minQueryLength) {
          return const _SearchEmptyState(message: '请至少输入 2 个字符');
        }
        return FutureBuilder<List<MediaItem>>(
          future: _searchAll(repository, libraryProvider, q),
          key: ValueKey('search_${q}_$refresh'),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _SearchLoadingGrid();
            }

            if (snapshot.hasError) {
              return _SearchErrorState(
                message: '搜索失败了，请重试。',
                onRetry: () => needsRefresh.value++,
              );
            }

            final items = snapshot.data ?? const [];

            if (items.isEmpty) {
              return _SearchEmptyState(
                message: '没有找到「$q」相关的内容',
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 720
                    ? 4
                    : constraints.maxWidth >= 480
                        ? 3
                        : 2;
                final spacing = constraints.maxWidth >= 720 ? 18.0 : 12.0;

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: 2 / 3,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return PosterCard(
                      mediaItem: item,
                      isFavorite: item.isFavorite,
                      progress: item.playbackProgress?.fraction ?? 0,
                      onTap: () => widget.onItemSelected(
                        _resolveNavigationTarget(item),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<MediaItem>> _searchAll(
    IMediaRepository repository,
    MediaLibraryProvider libraryProvider,
    String q,
  ) async {
    final serverFuture = repository.search(q, limit: 50);
    final localResults = _searchLocal(libraryProvider, q);

    List<MediaItem> serverResults;
    try {
      serverResults = await serverFuture;
    } catch (_) {
      serverResults = const [];
    }

    final seen = <String>{};
    final merged = <MediaItem>[];

    for (final item in [...serverResults, ...localResults]) {
      if (seen.add(item.mediaKey)) {
        merged.add(item);
      }
    }

    return merged;
  }

  static List<MediaItem> _searchLocal(
    MediaLibraryProvider provider,
    String q,
  ) {
    if (q.isEmpty) return const [];

    final allItems = provider.state.libraryItems.values
        .expand((items) => items)
        .take(MeowSearchDelegate._localSearchMaxItems)
        .toList(growable: false);

    if (allItems.isEmpty) return const [];

    final lower = q.toLowerCase();
    final isSingleChar = lower.length == 1;

    final scored = <_ScoredItem>[];

    for (final item in allItems) {
      final score = _fuzzyScore(lower, item, isSingleChar: isSingleChar);
      if (score > 0) {
        scored.add(_ScoredItem(item, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.map((s) => s.item).take(50).toList(growable: false);
  }

  static int _fuzzyScore(
    String lowerQuery,
    MediaItem item, {
    required bool isSingleChar,
  }) {
    final title = item.title.toLowerCase();
    final originalTitle = item.originalTitle.toLowerCase();
    final parentTitle = item.parentTitle?.toLowerCase() ?? '';
    int bestScore = 0;

    for (final text in [title, originalTitle, parentTitle]) {
      if (text.isEmpty) continue;
      final score = _matchScore(lowerQuery, text, isSingleChar: isSingleChar);
      if (score > bestScore) bestScore = score;
    }

    return bestScore;
  }

  static int _matchScore(
    String query,
    String text, {
    required bool isSingleChar,
  }) {
    if (query.isEmpty || text.isEmpty) return 0;

    if (text.contains(query)) {
      final pos = text.indexOf(query);
      return 1000 - pos;
    }

    if (!isSingleChar) {
      int qi = 0;
      for (int ti = 0; ti < text.length && qi < query.length; ti++) {
        if (text[ti] == query[qi]) qi++;
      }
      if (qi == query.length) return 500;
    }

    return 0;
  }

  MediaItem _resolveNavigationTarget(MediaItem item) {
    final seriesId = item.seriesId;
    if (seriesId != null && seriesId.isNotEmpty) {
      return item.copyWith(
        sourceId: seriesId,
        id: seriesId.hashCode,
        title: item.parentTitle ?? item.title,
        originalTitle: item.parentTitle ?? item.originalTitle,
        type: MediaType.series,
        parentTitle: null,
        seriesId: null,
      );
    }
    return item;
  }
}

class _ScoredItem {
  const _ScoredItem(this.item, this.score);
  final MediaItem item;
  final int score;
}

class _SearchLoadingGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2 / 3,
      ),
      itemCount: 6,
      itemBuilder: (c, i) => const PosterCardSkeleton(),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 48, color: Colors.white54),
                const SizedBox(height: 16),
                Text(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: onRetry, child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_rounded, size: 52, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              message ?? '输入关键词搜索电影和剧集',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
