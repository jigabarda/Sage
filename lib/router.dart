import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/episodes/episode_editor_screen.dart';
import 'features/history/history_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/placeholder_screen.dart';
import 'features/today/today_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Every route in the app.
///
/// A `StatefulShellRoute` per tab so each keeps its own stack — leaving
/// History mid-scroll to check Patterns and coming back to the top would be a
/// small cruelty on a bad day.
///
/// The editor sits on the *root* navigator rather than inside a branch, so it
/// covers the bottom bar. It is reached from two tabs and is a focused task;
/// leaving the tabs visible under it invites a stray tap that loses the form.
GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/today',
    routes: [
      GoRoute(
        path: '/episode/new',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const EpisodeEditorScreen(),
      ),
      GoRoute(
        path: '/episode/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            EpisodeEditorScreen(episodeId: state.pathParameters['id']),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (_, _) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/patterns',
                builder: (_, _) => const PlaceholderScreen(
                  title: 'Patterns',
                  phase: 'Phase 3',
                  summary:
                      'What the record shows, as arithmetic over your own '
                      'rows. Each finding states the numbers it came from.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const PlaceholderScreen(
                  title: 'Settings',
                  phase: 'Phase 1',
                  summary: 'Appearance, medications, and the doctor export.',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
