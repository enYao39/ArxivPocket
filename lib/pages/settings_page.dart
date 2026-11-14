import "package:arxiv/pages/how_to_use.dart";
import "package:arxiv/services/app_update_service.dart";
import "package:arxiv/services/main_page_style_store.dart";
import "package:arxiv/services/pdf_cache_store.dart";
import "package:arxiv/theme/app_theme.dart";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:hive/hive.dart";
import "package:theme_provider/theme_provider.dart";
import "package:url_launcher/url_launcher.dart";

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final PdfCacheStore _pdfCacheStore = PdfCacheStore();
  final AppUpdateService _updateService = AppUpdateService();
  var toolsOn = true;
  bool _checkingUpdate = false;
  int _pdfCacheLimitMb = PdfCacheStore.defaultMaxCacheMb;
  int _cachedPdfCount = 0;
  int _cachedPdfBytes = 0;

  Future<void> _loadCacheInfo() async {
    final limitMb = await _pdfCacheStore.loadMaxCacheMb();
    final stats = await _pdfCacheStore.getCacheStats();
    if (!mounted) return;
    setState(() {
      _pdfCacheLimitMb = limitMb;
      _cachedPdfCount = stats.fileCount;
      _cachedPdfBytes = stats.totalBytes;
    });
  }

  Future<void> _pickCacheLimit() async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text("PDF Cache Limit"),
        children: PdfCacheStore.limitOptionsMb
            .map(
              (mb) => RadioListTile<int>(
                value: mb,
                groupValue: _pdfCacheLimitMb,
                title: Text(PdfCacheStore.formatLimitLabel(mb)),
                onChanged: (value) => Navigator.pop(dialogContext, value),
              ),
            )
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _pdfCacheStore.saveMaxCacheMb(chosen);
    await _loadCacheInfo();
  }

  Future<void> _clearPdfCache() async {
    await _pdfCacheStore.clearCache();
    await _loadCacheInfo();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("PDF cache cleared.")));
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
    });

    try {
      final info = await _updateService.checkForUpdate();
      if (!mounted) return;
      if (info.hasUpdate) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              info.releaseName?.isNotEmpty == true
                  ? info.releaseName!
                  : "Update available (v${info.latestVersion})",
            ),
            content: SingleChildScrollView(
              child: Text(
                info.releaseNotes?.isNotEmpty == true
                    ? "Current: v${info.currentVersion}\nLatest: v${info.latestVersion}\n\n${info.releaseNotes}"
                    : "A new version (v${info.latestVersion}) is available. You are on v${info.currentVersion}.",
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Later"),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  launchUrl(
                    Uri.parse(info.apkDownloadUrl ?? info.releaseUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: Text(
                  info.apkDownloadUrl != null ? "Download APK" : "View Release",
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "You're on the latest version (v${info.currentVersion}).",
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      if (status == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("No published GitHub releases found yet."),
            action: SnackBarAction(
              label: "Releases",
              onPressed: () {
                launchUrl(
                  Uri.parse(AppUpdateService.releasesPageUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not check for updates: ${e.message ?? e}"),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Could not check for updates: $e")));
    } finally {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
        });
      }
    }
  }

  Future<void> saveToolsSetting(bool value) async {
    final toolsBox = await Hive.openBox("toolsBox");
    await toolsBox.put("toolsBox", value);
    await toolsBox.close();

    if (!mounted) return;
    setState(() {
      toolsOn = value;
    });
  }

  Future<void> loadToolsSetting() async {
    final toolsBox = await Hive.openBox("toolsBox");
    final savedToolsOn = await toolsBox.get("toolsBox") ?? true;
    await toolsBox.close();

    if (!mounted) return;
    setState(() {
      toolsOn = savedToolsOn;
    });
  }

  @override
  void initState() {
    super.initState();
    loadToolsSetting();
    _loadCacheInfo();
    MainPageStyleStore().ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTheme = ThemeProvider.themeOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(12.0),
        children: [
          _SettingsSectionLabel(
            label: "Interface",
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8.0),
          _SettingsActionTile(
            icon: Icons.palette_outlined,
            title: "Appearance",
            subtitle: currentTheme.description,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AppearanceSettingsPage(),
                ),
              );
            },
          ),
          ValueListenableBuilder<MainPageStyleSettings>(
            valueListenable: MainPageStyleStore.notifier,
            builder: (context, styleSettings, _) {
              final subtitle = styleSettings.limitAuthors
                  ? "Authors limited to ${styleSettings.maxAuthors}"
                  : "Show all authors";
              return _SettingsActionTile(
                icon: Icons.view_agenda_outlined,
                title: "Main Page Style",
                subtitle: subtitle,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MainPageStyleSettingsPage(),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 18.0),
          _SettingsSectionLabel(
            label: "AI Chat",
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8.0),
          _SettingsSwitchTile(
            icon: Icons.auto_fix_high_outlined,
            title: "Message tools",
            subtitle: "Enables Speak, Copy, and Share for AI replies.",
            value: toolsOn,
            onChanged: saveToolsSetting,
          ),
          const SizedBox(height: 18.0),
          _SettingsSectionLabel(
            label: "Storage & Cache",
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8.0),
          _SettingsActionTile(
            icon: Icons.storage_outlined,
            title: "PDF Cache Limit",
            subtitle:
                "${PdfCacheStore.formatLimitLabel(_pdfCacheLimitMb)} • Deletes oldest PDFs first",
            onTap: _pickCacheLimit,
          ),
          _SettingsActionTile(
            icon: Icons.cleaning_services_outlined,
            title: "Clear PDF Cache",
            subtitle:
                "$_cachedPdfCount files • ${PdfCacheStore.formatBytes(_cachedPdfBytes)}",
            onTap: _cachedPdfCount > 0 ? _clearPdfCache : () {},
          ),
          const SizedBox(height: 18.0),
          _SettingsSectionLabel(
            label: "Help",
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8.0),
          _SettingsActionTile(
            icon: Icons.help_outline,
            title: "How to Use",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HowToUsePage()),
              );
            },
          ),
          _SettingsActionTile(
            icon: Icons.system_update_outlined,
            title: "Check for Updates",
            subtitle: _checkingUpdate
                ? "Checking for updates..."
                : "Current version: v${AppUpdateService.currentVersion}",
            onTap: _checkForUpdates,
          ),
        ],
      ),
    );
  }
}

class MainPageStyleSettingsPage extends StatefulWidget {
  const MainPageStyleSettingsPage({super.key});

  @override
  State<MainPageStyleSettingsPage> createState() =>
      _MainPageStyleSettingsPageState();
}

class _MainPageStyleSettingsPageState extends State<MainPageStyleSettingsPage> {
  final MainPageStyleStore _store = MainPageStyleStore();
  static const _authorLimitOptions = [3, 5, 8];

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Main Page Style")),
      body: ValueListenableBuilder<MainPageStyleSettings>(
        valueListenable: MainPageStyleStore.notifier,
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(12.0),
            children: [
              _SettingsSectionLabel(
                label: "Authors",
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8.0),
              _SettingsSwitchTile(
                icon: Icons.people_outline,
                title: "Limit displayed authors",
                subtitle: settings.limitAuthors
                    ? "Hides extra authors when a paper has more than ${settings.maxAuthors}."
                    : "Shows the full author list on main page cards.",
                value: settings.limitAuthors,
                onChanged: (value) {
                  _store.save(settings.copyWith(limitAuthors: value));
                },
              ),
              if (settings.limitAuthors)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: subtleSurfaceColor(colorScheme),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Max visible authors",
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Wrap(
                        spacing: 8.0,
                        children: _authorLimitOptions.map((count) {
                          final selected = settings.maxAuthors == count;
                          return ChoiceChip(
                            label: Text("$count"),
                            selected: selected,
                            onSelected: (_) {
                              _store.save(settings.copyWith(maxAuthors: count));
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18.0),
              _SettingsSwitchTile(
                icon: Icons.filter_alt_off_outlined,
                title: "Exclude cross-listed papers",
                subtitle:
                    "Only show papers whose primary category matches the selected category.",
                value: settings.excludeCrossListed,
                onChanged: (value) {
                  _store.save(settings.copyWith(excludeCrossListed: value));
                },
              ),
              const SizedBox(height: 20.0),
              _SettingsSectionLabel(
                label: "Startup",
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8.0),
              _SettingsSwitchTile(
                icon: Icons.history,
                title: "Reopen last session",
                subtitle: settings.restoreSearchFilter
                    ? "Restores your last category, search filter, sort order, and page on launch."
                    : "Restores your last category, sort order, and page size on launch.",
                value: settings.restoreLastSession,
                onChanged: (value) {
                  _store.save(settings.copyWith(restoreLastSession: value));
                },
              ),
              if (settings.restoreLastSession) ...[
                const SizedBox(height: 10.0),
                _SettingsSwitchTile(
                  icon: Icons.manage_search,
                  title: "Also restore search filter",
                  subtitle:
                      "Keep your previous search query, advanced filters, and page offset on launch.",
                  value: settings.restoreSearchFilter,
                  onChanged: (value) {
                    _store.save(settings.copyWith(restoreSearchFilter: value));
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = ThemeProvider.controllerOf(context);
    final selectedThemeId = ThemeProvider.themeOf(context).id;
    final pairedThemeId = pairedBrightnessThemeId(selectedThemeId);
    final isDark = colorScheme.brightness == Brightness.dark;
    final themes = controller.allThemes;

    return Scaffold(
      appBar: AppBar(title: const Text("Appearance")),
      body: ListView(
        padding: const EdgeInsets.all(12.0),
        children: [
          _SettingsSectionLabel(
            label: "Theme",
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8.0),
          _SettingsSwitchTile(
            icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            title: "Dark mode",
            subtitle: "Switches the current theme between light and dark.",
            value: isDark,
            onChanged: (_) {
              if (controller.hasTheme(pairedThemeId)) {
                controller.setTheme(pairedThemeId);
              }
            },
          ),
          const SizedBox(height: 4.0),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: themes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8.0,
              mainAxisSpacing: 8.0,
              childAspectRatio: 1.65,
            ),
            itemBuilder: (context, index) {
              final theme = themes[index];
              return _ThemeOptionTile(
                theme: theme,
                selected: theme.id == selectedThemeId,
                onSelected: () => controller.setTheme(theme.id),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.theme,
    required this.selected,
    required this.onSelected,
  });

  final AppTheme theme;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final previewScheme = theme.data.colorScheme;

    return _SettingsTileShell(
      selected: selected,
      onTap: onSelected,
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ThemeSwatches(colorScheme: previewScheme),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          Text(
            theme.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatches extends StatelessWidget {
  const _ThemeSwatches({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58.0,
      height: 34.0,
      child: Stack(
        children: [
          _Swatch(color: colorScheme.surface, left: 0.0, top: 0.0, size: 34.0),
          _Swatch(
            color: colorScheme.primaryContainer,
            left: 18.0,
            top: 0.0,
            size: 34.0,
          ),
          _Swatch(color: colorScheme.primary, left: 36.0, top: 0.0, size: 22.0),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.left,
    required this.top,
    required this.size,
  });

  final Color color;
  final double left;
  final double top;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _SettingsTileShell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2.0),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12.0,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _SettingsTileShell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingsTileShell extends StatelessWidget {
  const _SettingsTileShell({
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
    this.selected = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : subtleSurfaceColor(colorScheme),
        borderRadius: BorderRadius.circular(10.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(10.0),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
