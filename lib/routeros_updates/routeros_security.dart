import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Official RouterOS security information used by the app.
///
/// This catalogue is deliberately conservative: it only contains releases
/// explicitly named by MikroTik as carrying a security fix. It does not infer
/// vulnerabilities from ordinary changelog wording.
class RouterOsSecurityCatalog {
  static const sourceUrl = 'https://mikrotik.com/supportsec';

  final String advisoryId;
  final List<String> fixedVersions;
  final DateTime publishedAt;
  final DateTime? checkedAt;
  final bool fromLiveSource;

  const RouterOsSecurityCatalog({
    required this.advisoryId,
    required this.fixedVersions,
    required this.publishedAt,
    this.checkedAt,
    this.fromLiveSource = false,
  });

  static final bundled = RouterOsSecurityCatalog(
    advisoryId: 'mikrotik-security-2026-09',
    fixedVersions: const ['7.25beta3', '7.24.2', '7.23.4', '6.49.21'],
    publishedAt: DateTime.utc(2026, 9, 3),
  );

  Map<String, Object?> toJson() => {
        'advisoryId': advisoryId,
        'fixedVersions': fixedVersions,
        'publishedAt': publishedAt.toIso8601String(),
        'checkedAt': checkedAt?.toIso8601String(),
      };

  static RouterOsSecurityCatalog? fromJson(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final fixed = (json['fixedVersions'] as List?)
          ?.whereType<String>()
          .where((version) => RouterOsVersion.tryParse(version) != null)
          .toList();
      final published = DateTime.tryParse(json['publishedAt'] as String? ?? '');
      final checked = DateTime.tryParse(json['checkedAt'] as String? ?? '');
      if (fixed == null || fixed.isEmpty || published == null) return null;
      return RouterOsSecurityCatalog(
        advisoryId: json['advisoryId'] as String? ?? bundled.advisoryId,
        fixedVersions: List.unmodifiable(fixed),
        publishedAt: published,
        checkedAt: checked,
        fromLiveSource: checked != null,
      );
    } catch (_) {
      return null;
    }
  }
}

class RouterOsSecurityStatus {
  final String host;
  final String installedVersion;
  final String fixedVersion;
  final RouterOsSecurityCatalog catalog;

  const RouterOsSecurityStatus({
    required this.host,
    required this.installedVersion,
    required this.fixedVersion,
    required this.catalog,
  });
}

/// A small RouterOS version parser that understands stable, alpha, beta and RC
/// suffixes. RouterOS versions are not plain SemVer (`7.25beta3`), so package
/// version comparators are not appropriate here.
class RouterOsVersion implements Comparable<RouterOsVersion> {
  final int major;
  final int minor;
  final int patch;
  final String stage;
  final int stageNumber;

  const RouterOsVersion(
    this.major,
    this.minor,
    this.patch,
    this.stage,
    this.stageNumber,
  );

  static RouterOsVersion? tryParse(String raw) {
    final match = RegExp(
      r'^\s*(\d+)\.(\d+)(?:\.(\d+))?(?:(alpha|beta|rc)\s*(\d+))?',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return null;
    return RouterOsVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.tryParse(match.group(3) ?? '') ?? 0,
      (match.group(4) ?? 'stable').toLowerCase(),
      int.tryParse(match.group(5) ?? '') ?? 0,
    );
  }

  int get _stageRank => switch (stage) {
        'alpha' => 0,
        'beta' => 1,
        'rc' => 2,
        _ => 3,
      };

  @override
  int compareTo(RouterOsVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (_stageRank, other._stageRank),
      (stageNumber, other.stageNumber),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }
}

class RouterOsSecurityService {
  static const _cacheKey = 'routeros_security_catalog_v1';
  static const _maxResponseBytes = 512 * 1024;
  static const _cacheTtl = Duration(hours: 24);
  static final instance = RouterOsSecurityService();

  final http.Client? _client;
  RouterOsSecurityCatalog _current = RouterOsSecurityCatalog.bundled;
  Future<RouterOsSecurityCatalog>? _refreshInFlight;

  RouterOsSecurityService({http.Client? client}) : _client = client;

  RouterOsSecurityCatalog get currentCatalog => _current;

  Future<RouterOsSecurityCatalog> catalog({bool allowNetwork = true}) async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // A platform store can be unavailable during very early startup or in a
      // headless/unit-test environment. Security advice must remain optional
      // and fall back to the bundled catalogue rather than fail a connection.
      return _current;
    }
    final cached = RouterOsSecurityCatalog.fromJson(
      prefs.getString(_cacheKey) ?? '',
    );
    if (cached != null &&
        cached.publishedAt.compareTo(_current.publishedAt) >= 0) {
      _current = cached;
    }

    final checkedAt = _current.checkedAt;
    final fresh = checkedAt != null &&
        DateTime.now().toUtc().difference(checkedAt.toUtc()) < _cacheTtl;
    if (!allowNetwork || fresh) return _current;

    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final refresh = _downloadAndCache(prefs);
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<RouterOsSecurityCatalog> _downloadAndCache(
    SharedPreferences prefs,
  ) async {
    try {
      final uri = Uri.parse(RouterOsSecurityCatalog.sourceUrl);
      final response = _client == null
          ? await http.get(uri).timeout(const Duration(seconds: 8))
          : await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > _maxResponseBytes) {
        return _current;
      }
      final parsed = parseOfficialSecurityPage(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        checkedAt: DateTime.now().toUtc(),
      );
      if (parsed == null ||
          parsed.publishedAt.compareTo(_current.publishedAt) < 0) {
        return _current;
      }
      _current = parsed;
      await prefs.setString(_cacheKey, jsonEncode(parsed.toJson()));
    } catch (_) {
      // Offline and captive-portal use is normal. The signed app still carries
      // a dated conservative fallback and never weakens TLS for this request.
    }
    return _current;
  }

  RouterOsSecurityStatus? evaluate({
    required String host,
    required String installedVersion,
    RouterOsSecurityCatalog? catalog,
  }) {
    final installed = RouterOsVersion.tryParse(installedVersion);
    if (installed == null) return null;
    final source = catalog ?? _current;
    final fixes = source.fixedVersions
        .map((raw) => (raw: raw, parsed: RouterOsVersion.tryParse(raw)))
        .where((entry) => entry.parsed != null)
        .where((entry) => entry.parsed!.major == installed.major)
        .toList();
    if (fixes.isEmpty) return null;

    // Prefer the fix for the exact release branch. For an older branch, use
    // the nearest fixed branch that follows it. Never guess about a newer
    // development branch absent from the official list.
    var candidates =
        fixes.where((entry) => entry.parsed!.minor == installed.minor).toList();
    candidates = candidates.isNotEmpty
        ? candidates
        : fixes
            .where((entry) => entry.parsed!.minor > installed.minor)
            .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.parsed!.compareTo(b.parsed!));
    final target = candidates.first;
    if (installed.compareTo(target.parsed!) >= 0) return null;
    return RouterOsSecurityStatus(
      host: host,
      installedVersion: installedVersion.trim(),
      fixedVersion: target.raw,
      catalog: source,
    );
  }

  /// Extracts the newest official announcement only when it explicitly says
  /// that this is an important security update and lists fixed releases.
  static RouterOsSecurityCatalog? parseOfficialSecurityPage(
    String html, {
    required DateTime checkedAt,
  }) {
    final text = html
        .replaceAll(
            RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ');
    final start = text.indexOf('Security Announcements');
    final fixStart = text.indexOf('Fix is included in:', start < 0 ? 0 : start);
    if (fixStart < 0) return null;
    final prefix = text.substring(start < 0 ? 0 : start, fixStart);
    if (!prefix.toLowerCase().contains('important security update')) {
      return null;
    }
    var end = text.indexOf('Steps after upgrade', fixStart);
    if (end < 0) end = (fixStart + 500).clamp(0, text.length);
    final fixedBlock = text.substring(fixStart, end);
    final versions = RegExp(
      r'\b(?:6|7)\.\d+(?:\.\d+)?(?:\s*(?:alpha|beta|rc)\s*\d+)?\b',
      caseSensitive: false,
    )
        .allMatches(fixedBlock)
        .map((match) => match.group(0)!.replaceAll(RegExp(r'\s+'), ''))
        .toSet()
        .toList();
    if (versions.isEmpty) return null;

    final dateMatch = RegExp(
      r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),\s+(\d{4})',
      caseSensitive: false,
    ).allMatches(prefix).lastOrNull;
    final month = dateMatch == null ? null : _month(dateMatch.group(1)!);
    final published = dateMatch == null || month == null
        ? RouterOsSecurityCatalog.bundled.publishedAt
        : DateTime.utc(
            int.parse(dateMatch.group(3)!),
            month,
            int.parse(dateMatch.group(2)!),
          );
    return RouterOsSecurityCatalog(
      advisoryId:
          'mikrotik-security-${published.year}-${published.month.toString().padLeft(2, '0')}',
      fixedVersions: List.unmodifiable(versions),
      publishedAt: published,
      checkedAt: checkedAt,
      fromLiveSource: true,
    );
  }

  static int? _month(String name) => const {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      }[name.toLowerCase()];
}

extension<T> on Iterable<T> {
  T? get lastOrNull {
    T? result;
    for (final value in this) {
      result = value;
    }
    return result;
  }
}
