import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/mappers/media_service_config_serializer.dart';
import '../../domain/entities/media_service_config.dart';

class PersistedFileSource {
  const PersistedFileSource({
    required this.id,
    required this.name,
    required this.config,
  });

  final String id;
  final String name;
  final MediaServiceConfig config;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'name': name, 'config': MediaServiceConfigSerializer.toJson(config)};
  }

  factory PersistedFileSource.fromJson(Map<String, dynamic> json) {
    return PersistedFileSource(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      config: MediaServiceConfigSerializer.fromJson(
        (json['config'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class PersistedFileSourceState {
  const PersistedFileSourceState({
    this.sources = const [],
    this.selectedSourceId,
  });

  final List<PersistedFileSource> sources;
  final String? selectedSourceId;

  bool get isEmpty => sources.isEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'selectedSourceId': selectedSourceId,
      'sources': sources
          .map((source) => source.toJson())
          .toList(growable: false),
    };
  }

  factory PersistedFileSourceState.fromJson(Map<String, dynamic> json) {
    final sources = (json['sources'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => PersistedFileSource.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);

    return PersistedFileSourceState(
      sources: sources,
      selectedSourceId: json['selectedSourceId']?.toString().trim(),
    );
  }
}

class FileSourceStore {
  static const String _fileName = 'media_sources.json';
  static const String _webStorageKey = 'media_sources_json';

  Future<PersistedFileSourceState> load() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_webStorageKey);
      if (raw == null || raw.trim().isEmpty) {
        return const PersistedFileSourceState();
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const PersistedFileSourceState();
      }

      return PersistedFileSourceState.fromJson(decoded);
    }

    final file = await _resolveFile();
    if (!await file.exists()) {
      return const PersistedFileSourceState();
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const PersistedFileSourceState();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const PersistedFileSourceState();
    }

    return PersistedFileSourceState.fromJson(decoded);
  }

  Future<void> save(PersistedFileSourceState state) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _webStorageKey,
        const JsonEncoder.withIndent('  ').convert(state.toJson()),
      );
      return;
    }

    final file = await _resolveFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_webStorageKey);
      return;
    }

    final file = await _resolveFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _resolveFile() async {
    final directory = await getApplicationSupportDirectory();
    final configDirectory = Directory('${directory.path}/config');
    if (!await configDirectory.exists()) {
      await configDirectory.create(recursive: true);
    }

    return File('${configDirectory.path}/$_fileName');
  }
}
