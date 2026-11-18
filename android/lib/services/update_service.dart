import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

class FlikUpdate {
  final String version;
  final String tagName;
  final String releaseUrl;
  final String apkUrl;

  const FlikUpdate({
    required this.version,
    required this.tagName,
    required this.releaseUrl,
    required this.apkUrl,
  });
}

class UpdateService {
  static const _updatesChannel = MethodChannel('flik/updates');
  static const _releasesApi = 'https://api.github.com/repos/ashoka-2/Flik/releases?per_page=30';
  static const _releasePrefix = 'https://github.com/ashoka-2/Flik/releases/tag/';
  static const _downloadPrefix = 'https://github.com/ashoka-2/Flik/releases/download/';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 8),
    headers: const {'Accept': 'application/vnd.github+json'},
  ));

  Future<FlikUpdate?> checkForUpdate() async {
    final currentVersion = await _updatesChannel.invokeMethod<String>('getVersion') ?? '0.0.0';
    final response = await _dio.get<dynamic>(_releasesApi);
    final releases = response.data;
    if (releases is! List) return null;

    FlikUpdate? newest;
    for (final value in releases) {
      if (value is! Map) continue;
      final release = Map<String, dynamic>.from(value);
      if (release['draft'] == true) continue;

      final tag = release['tag_name'] as String?;
      final releaseUrl = release['html_url'] as String?;
      final assets = release['assets'];
      if (tag == null || releaseUrl == null || assets is! List) continue;
      if (!releaseUrl.startsWith(_releasePrefix)) continue;

      String? apkUrl;
      for (final asset in assets) {
        if (asset is Map && (asset['name'] as String?)?.toLowerCase() == 'app-release.apk') {
          final candidate = asset['browser_download_url'] as String?;
          if (candidate != null && candidate.startsWith(_downloadPrefix)) apkUrl = candidate;
          break;
        }
      }
      if (apkUrl == null) continue;

      final version = _versionFromTag(tag);
      if (version == null || _compareVersions(version, currentVersion) <= 0) continue;
      final candidate = FlikUpdate(version: version, tagName: tag, releaseUrl: releaseUrl, apkUrl: apkUrl);
      if (newest == null || _compareVersions(candidate.version, newest.version) > 0) newest = candidate;
    }
    return newest;
  }

  String? _versionFromTag(String tag) {
    final match = RegExp(r'^v?(\d+(?:\.\d+){1,3})').firstMatch(tag);
    return match?.group(1);
  }

  int _compareVersions(String left, String right) {
    final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    for (var i = 0; i < 4; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
