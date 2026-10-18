import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/l10n/i18n.dart';
import 'core/theme.dart';
import 'data/app_state.dart';
import 'features/shell/shell.dart';

class RunLahApp extends StatelessWidget {
  const RunLahApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return ListenableBuilder(
      listenable: I18n.instance,
      builder: (context, _) => MaterialApp(
        // Rebuild every screen when the language changes.
        key: ValueKey(I18n.instance.lang),
        title: 'RunLah',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: settings.themeMode,
        home: const Shell(),
      ),
    );
  }
}
