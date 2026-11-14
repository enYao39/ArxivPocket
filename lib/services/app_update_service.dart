import 'package:dio/dio.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.installedTag,
    required this.latestTag,
    required this.hasUpdate,
    required this.releaseUrl,
    this.releaseName,
    this.releaseNotes,
    this.apkDownloadUrl,
  });

  final String currentVersion;
  final String installedTag;
  final String latestTag;
  final bool hasUpdate;
  final String releaseUrl;
  final String? releaseName;
  final String? releaseNotes;
  final String? apkDownloadUrl;
}

class AppUpdateService {
  static const String currentVersion = "3.0.5";
  static const String buildTag = String.fromEnvironment('RELEASE_TAG');
  static const String buildDateIso = String.fromEnvironment(
    'BUILD_DATE',
    defaultValue: '2026-11-14T12:25:00Z',
  );
  static const String _latestReleaseApiUrl =
      "https://api.github.com/repos/enYao39/ArxivPocket/releases/latest";
  static const String releasesPageUrl =
      "https://github.com/enYao39/ArxivPocket/releases";

  static String get displayInstalledVersion =>
      buildTag.isNotEmpty ? buildTag : "v$currentVersion";

  final Dio _dio;

  AppUpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {
                "Accept": "application/vnd.github+json",
                "User-Agent": "ArxivPocket/$currentVersion",
              },
            ),
          );

  Future<AppUpdateInfo> checkForUpdate() async {
    final response = await _dio.get<Map<String, dynamic>>(_latestReleaseApiUrl);
    final data = response.data;
    if (data == null) {
      throw const FormatException("Empty response from GitHub Releases.");
    }

    final tagName = (data["tag_name"] ?? "").toString().trim();
    final publishedAtRaw = (data["published_at"] ?? "").toString().trim();
    final publishedAt = DateTime.tryParse(publishedAtRaw)?.toUtc();
    final releaseUrl = (data["html_url"] ?? releasesPageUrl).toString().trim();
    final releaseName = data["name"]?.toString().trim();
    final releaseNotes = data["body"]?.toString().trim();

    String? apkUrl;
    final assets = data["assets"];
    if (assets is List) {
      for (final asset in assets.whereType<Map>()) {
        final name = (asset["name"] ?? "").toString().toLowerCase();
        if (name.endsWith(".apk")) {
          apkUrl = asset["browser_download_url"]?.toString();
          break;
        }
      }
    }

    final hasUpdate = evaluateHasUpdate(
      latestTag: tagName,
      publishedAt: publishedAt,
    );

    return AppUpdateInfo(
      currentVersion: currentVersion,
      installedTag: displayInstalledVersion,
      latestTag: tagName.isEmpty ? "unknown" : tagName,
      hasUpdate: hasUpdate,
      releaseUrl: releaseUrl,
      releaseName: releaseName,
      releaseNotes: releaseNotes,
      apkDownloadUrl: apkUrl,
    );
  }

  static bool evaluateHasUpdate({
    required String latestTag,
    DateTime? publishedAt,
    String installedTag = buildTag,
    String installedBuildDateIso = buildDateIso,
  }) {
    final trimmedTag = latestTag.trim();
    if (trimmedTag.isEmpty) return false;

    // When built by a GitHub Release workflow, compare exact release tags so
    // custom release tags work without bumping pubspec.yaml.
    if (installedTag.trim().isNotEmpty) {
      return trimmedTag != installedTag.trim();
    }

    if (isNewerVersion(trimmedTag, currentVersion)) {
      return true;
    }

    final buildDate = DateTime.tryParse(installedBuildDateIso)?.toUtc();
    if (publishedAt != null && buildDate != null) {
      return publishedAt.toUtc().isAfter(buildDate);
    }

    return false;
  }

  static String normalizeVersion(String raw) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final plusIndex = trimmed.indexOf('+');
    final withoutBuild = plusIndex >= 0
        ? trimmed.substring(0, plusIndex)
        : trimmed;
    final dashIndex = withoutBuild.indexOf('-');
    return dashIndex >= 0 ? withoutBuild.substring(0, dashIndex) : withoutBuild;
  }

  static bool isNewerVersion(String candidate, String current) {
    final a = normalizeVersion(candidate)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final b = normalizeVersion(current)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

    final maxLen = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < maxLen; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return false;
  }
}
