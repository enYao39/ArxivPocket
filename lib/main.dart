import "dart:async";

import "package:arxiv/models/bookmarks.dart";
import "package:arxiv/models/chat_message.dart";
import "package:arxiv/models/chat_thread.dart";
import "package:arxiv/models/paper.dart";
import "package:arxiv/models/paper_note.dart";
// import "package:arxiv/pages/home_page.dart";
import "package:arxiv/pages/splash_screen.dart";
import "package:arxiv/theme/app_theme.dart";
import "package:dynamic_color/dynamic_color.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_tex/flutter_tex.dart";
import "package:hive_flutter/hive_flutter.dart";
import "package:theme_provider/theme_provider.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(BookmarkAdapter());
  Hive.registerAdapter(PaperAdapter());
  Hive.registerAdapter(RoleAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  Hive.registerAdapter(ChatThreadAdapter());
  Hive.registerAdapter(PaperNoteAdapter());
  unawaited(
    TeXRenderingServer.start()
        .timeout(const Duration(seconds: 3))
        .catchError((_) {}),
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

ColorScheme? _toFlutterColorScheme(dynamic scheme) {
  if (scheme == null) {
    return null;
  }
  return ColorScheme(
    brightness: scheme.brightness as Brightness,
    primary: scheme.primary as Color,
    onPrimary: scheme.onPrimary as Color,
    primaryContainer: scheme.primaryContainer as Color,
    onPrimaryContainer: scheme.onPrimaryContainer as Color,
    secondary: scheme.secondary as Color,
    onSecondary: scheme.onSecondary as Color,
    secondaryContainer: scheme.secondaryContainer as Color,
    onSecondaryContainer: scheme.onSecondaryContainer as Color,
    tertiary: scheme.tertiary as Color,
    onTertiary: scheme.onTertiary as Color,
    tertiaryContainer: scheme.tertiaryContainer as Color,
    onTertiaryContainer: scheme.onTertiaryContainer as Color,
    error: scheme.error as Color,
    onError: scheme.onError as Color,
    errorContainer: scheme.errorContainer as Color,
    onErrorContainer: scheme.onErrorContainer as Color,
    surface: scheme.surface as Color,
    onSurface: scheme.onSurface as Color,
    onSurfaceVariant: scheme.onSurfaceVariant as Color,
    outline: scheme.outline as Color,
    outlineVariant: scheme.outlineVariant as Color,
    shadow: scheme.shadow as Color,
    scrim: scheme.scrim as Color,
    inverseSurface: scheme.inverseSurface as Color,
    onInverseSurface: scheme.onInverseSurface as Color,
    inversePrimary: scheme.inversePrimary as Color,
    surfaceTint: scheme.surfaceTint as Color,
  );
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => ThemeProvider(
        defaultThemeId: "light_theme",
        saveThemesOnChange: true,
        loadThemeOnInit: true,
        themes: buildAppThemes(
          _toFlutterColorScheme(lightDynamic),
          _toFlutterColorScheme(darkDynamic),
        ),
        child: Builder(
          builder: (themeContext) {
            final theme = ThemeProvider.themeOf(themeContext).data;
            final colorScheme = theme.colorScheme;
            final isDark = colorScheme.brightness == Brightness.dark;
            final overlayIconBrightness = isDark
                ? Brightness.light
                : Brightness.dark;

            SystemChrome.setSystemUIOverlayStyle(
              SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: overlayIconBrightness,
                statusBarBrightness: isDark
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: colorScheme.surface,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: overlayIconBrightness,
              ),
            );

            return MaterialApp(
              theme: theme,
              debugShowCheckedModeBanner: false,
              initialRoute: "/",
              // routes: {"/": (context) => const HomePage()},
              routes: {"/": (context) => const SplashScreen()},
            );
          },
        ),
      ),
    );
  }
}
