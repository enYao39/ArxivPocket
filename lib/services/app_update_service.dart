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
  static const String _latestReleaseWebUrl =
      "https://github.com/enYao39/ArxivPocket/releases/latest";
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
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: true,
              maxRedirects: 5,
              headers: const {"User-Agent": "ArxivPocket/$currentVersion"},
            ),
          );

  Future<AppUpdateInfo> checkForUpdate() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _latestReleaseApiUrl,
        options: Options(
          headers: const {"Accept": "application/vnd.github+json"},
        ),
      );
      final data = response.data;
      if (data == null) {
        return _checkViaWebReleases();
      }

      final tagName = (data["tag_name"] ?? "").toString().trim();
      final publishedAtRaw = (data["published_at"] ?? "").toString().trim();
      final publishedAt = DateTime.tryParse(publishedAtRaw)?.toUtc();
      final releaseUrl = (data["html_url"] ?? releasesPageUrl)
          .toString()
          .trim();
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
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 403 || status == 429) {
        return _checkViaWebReleases();
      }
      rethrow;
    }
  }

  Future<AppUpdateInfo> _checkViaWebReleases() async {
    final response = await _dio.get<String>(
      _latestReleaseWebUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: const {"Accept": "text/html,application/xhtml+xml"},
      ),
    );
    final finalUri = response.realUri;
    final html = response.data ?? "";
    final tag = extractTagFromReleaseUri(finalUri) ?? extractTagFromHtml(html);
    if (tag == null || tag.isEmpty) {
      throw const FormatException("Could not determine latest release tag.");
    }

    final publishedAt = extractPublishedAtFromHtml(html);
    final releaseUrl =
        "https://github.com/enYao39/ArxivPocket/releases/tag/$tag";

    String? apkUrl;
    try {
      final assetsResponse = await _dio.get<String>(
        "https://github.com/enYao39/ArxivPocket/releases/expanded_assets/${Uri.encodeComponent(tag)}",
        options: Options(
          responseType: ResponseType.plain,
          headers: const {"Accept": "text/html"},
        ),
      );
      apkUrl = extractFirstApkUrlFromHtml(assetsResponse.data ?? "");
    } catch (_) {}

    final hasUpdate = evaluateHasUpdate(
      latestTag: tag,
      publishedAt: publishedAt,
    );

    return AppUpdateInfo(
      currentVersion: currentVersion,
      installedTag: displayInstalledVersion,
      latestTag: tag,
      hasUpdate: hasUpdate,
      releaseUrl: releaseUrl,
      releaseName: "Release $tag",
      apkDownloadUrl: apkUrl,
    );
  }

  static String? extractTagFromReleaseUri(Uri uri) {
    final segments = uri.pathSegments;
    final tagIndex = segments.indexOf('tag');
    if (tagIndex >= 0 && tagIndex + 1 < segments.length) {
      final tag = Uri.decodeComponent(segments[tagIndex + 1]).trim();
      return tag.isEmpty ? null : tag;
    }
    return null;
  }

  static String? extractTagFromHtml(String html) {
    final match = RegExp(
      r'/enYao39/ArxivPocket/releases/tag/([^"/?#<\s]+)',
    ).firstMatch(html);
    if (match == null) return null;
    return Uri.decodeComponent(match.group(1)!).trim();
  }

  static DateTime? extractPublishedAtFromHtml(String html) {
    final match = RegExp(
      r'<relative-time[^>]*datetime="([^"]+)"',
    ).firstMatch(html);
    if (match == null) return null;
    return DateTime.tryParse(match.group(1)!)?.toUtc();
  }

  static String? extractFirstApkUrlFromHtml(String html) {
    final match = RegExp(
      r'href="(/enYao39/ArxivPocket/releases/download/[^"]+\.apk)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return null;
    return "https://github.com${match.group(1)!}";
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
