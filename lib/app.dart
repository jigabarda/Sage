import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/brand_palette.dart';
import 'core/sage_theme.dart';
import 'core/theme_controller.dart';
import 'providers.dart';
import 'router.dart';

class SageApp extends ConsumerStatefulWidget {
  const SageApp({super.key});

  @override
  ConsumerState<SageApp> createState() => _SageAppState();
}

class _SageAppState extends ConsumerState<SageApp> {
  // Built once. Rebuilding a GoRouter on every theme change throws away the
  // navigation stack, which is how changing the accent used to bounce Sellora
  // back to the first tab.
  late final GoRouter _router = buildRouter();

  @override
  void initState() {
    super.initState();
    // Rebuilds the recurring schedule from current settings and current
    // content, so the weekly summary reflects what the log says now rather
    // than what it said whenever Settings was last opened. Fire and forget:
    // nothing on screen depends on it, and it swallows its own failures.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rearmNotificationsProvider.future).ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(brandPaletteProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Sage',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      themeMode: mode,
      theme: buildSageTheme(Brightness.light, palette),
      darkTheme: buildSageTheme(Brightness.dark, palette),
    );
  }
}
