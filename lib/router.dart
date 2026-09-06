import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/shell/app_shell.dart';
import 'features/shell/placeholder_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Every route in the app.
///
/// A `StatefulShellRoute` per tab so each keeps its own stack — leaving
/// History mid-scroll to check Patterns and coming back to the top would be a
/// small cruelty on a bad day.
GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/today',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (_, _) => const PlaceholderScreen(
                  title: 'Today',
                  phase: 'Phase 1',
                  summary:
                      'One tap to log an episode while it is happening, and '
                      'whatever is worth saying about right now.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (_, _) => const PlaceholderScreen(
                  title: 'History',
                  phase: 'Phase 1',
                  summary:
                      'Every episode logged, newest first. Edit one, close an '
                      'open one, or record what helped.',
                ),
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
