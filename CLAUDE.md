# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Analyze code
flutter analyze

# Build
flutter build apk      # Android
flutter build ios      # iOS
flutter build web      # Web
flutter build macos    # macOS
```

## Architecture

MeowHub is a Flutter media streaming app using **Clean Architecture** with **Provider** state management.

### Layer Structure

- `lib/domain/` — Pure business logic: entities (`WatchHistoryItem`), abstract repository interfaces, use cases
- `lib/data/` — Implementations: datasources (Emby remote + local in-memory), repository impls, data models
- `lib/models/` — App-level models (`MediaItem`, `Cast`) used across UI and providers
- `lib/providers/` — `AppProvider` (watch history, favorites, server selection, playback progress) and `MovieProvider` (media list loading state)
- `lib/ui/` — Presentation layer split into:
  - `atoms/` — small reusable widgets (PosterCard, MeowVideoPlayer, StatusPill, etc.)
  - `responsive/` — layout wrappers that delegate to mobile or tablet screens
  - `mobile/` and `tablet/` — platform-specific screen implementations
  - `widgets/` — composite widgets

### Responsive Layout

`ResponsiveLayoutBuilder` switches between mobile and tablet layouts based on screen width. Each major screen (home, detail, player) has both a `mobile/` and `tablet/` variant. The `responsive/` views act as the router-facing entry points.

### State Management

`MultiProvider` at the root provides `AppProvider` and `MovieProvider`. Both extend `ChangeNotifier`. UI reads state via `context.watch<AppProvider>()` / `context.read<AppProvider>()`.

### Routing

GoRouter with named routes defined in `main.dart`:
- `/` → home (3 tabs: movies, series, history)
- `/media/:id` → media detail
- `/player` → video player (receives `MediaItem` via `extra`)
- `/sample` → UI component demo

### Data Flow

Watch history merges two sources via `GetUnifiedHistoryUseCase`: `EmbyWatchHistoryRemoteDataSource` (currently mocked) and `LocalWatchHistoryDataSource` (in-memory). Results are sorted by `updatedAt` descending.

### Current State

All data sources are mocked — no real API integration exists yet. Device preview is enabled by default on desktop/web for development.
