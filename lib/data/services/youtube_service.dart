import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Servicio de búsqueda de videos de YouTube.
///
/// Estrategia:
///   - En WEB: llama a la Firebase Cloud Function `searchYoutube`
///     (servidor propio → sin CORS, sin bloqueos antibot de YouTube).
///   - En MÓVIL: scraping directo de YouTube + fallback Piped + Invidious,
///     con verificación de embeddability vía oEmbed.
class YouTubeService {
  static const _timeout = Duration(seconds: 15);
  static const _maxCandidates = 5;

  // Instancias públicas de Piped (solo móvil)
  static const _pipedInstances = [
    'https://pipedapi.in.projectsegfau.lt',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.kavin.rocks',
  ];

  // Instancias públicas de Invidious (solo móvil)
  static const _invidiousInstances = [
    'https://iv.ggtyler.dev',
    'https://invidious.slipfox.xyz',
    'https://invidious.privacyredirect.com',
  ];

  // ─────────────────────────────────────────────────────────────
  // PUNTO DE ENTRADA PÚBLICO
  // ─────────────────────────────────────────────────────────────

  /// Busca el videoId de YouTube para una canción.
  Future<String?> searchVideo(String title, String artist) async {
    if (kIsWeb) {
      return _searchWeb(title, artist);
    } else {
      return _searchMobile(title, artist);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // WEB: CORS Scrape & Invidious API
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchWeb(String title, String artist) async {
    final cleanTitle = _cleanTitle(title);

    final queries = [
      '$artist $cleanTitle',
      '$artist $title',
      '$artist $cleanTitle - Topic',
      '$artist $cleanTitle official audio',
    ];

    for (final q in queries) {
      // 1. YouTube Scraping a través del proxy CORS codetabs (muy fiable)
      final idScrape = await _searchYoutubeScrapeWeb(q);
      if (idScrape != null) {
        debugPrint('YT (Web) ✓ Scrape: $idScrape (query: "$q")');
        return idScrape;
      }

      // 2. Fallback: Invidious API directa con soporte CORS (inv.thepixora.com)
      final idInvidious = await _searchInvidiousWeb(q);
      if (idInvidious != null) {
        debugPrint('YT (Web) ✓ Invidious: $idInvidious (query: "$q")');
        return idInvidious;
      }
    }

    debugPrint('YT (Web) ✗ No se encontró video para "$artist $title"');
    return null;
  }

  Future<String?> _searchYoutubeScrapeWeb(String query) async {
    final ytSearchUrl =
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';
    final proxyUrl =
        'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(ytSearchUrl)}';

    try {
      final resp = await http.get(Uri.parse(proxyUrl)).timeout(_timeout);
      if (resp.statusCode != 200) return null;

      final body = resp.body;
      final seen = <String>{};
      final ids = <String>[];
      final pattern = RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"');

      for (final match in pattern.allMatches(body)) {
        if (ids.length >= _maxCandidates) break;
        final id = match.group(1)!;
        if (id != 'undefined' && id.length == 11 && seen.add(id)) {
          ids.add(id);
        }
      }

      if (ids.isNotEmpty) return ids.first;
    } catch (e) {
      debugPrint('YT (Web) Scrape error: $e');
    }
    return null;
  }

  Future<String?> _searchInvidiousWeb(String query) async {
    // Usamos inv.thepixora.com que tiene soporte CORS verificado y está online
    final url =
        'https://inv.thepixora.com/api/v1/search?q=${Uri.encodeComponent(query)}&type=video&fields=videoId';
    try {
      final resp = await http.get(Uri.parse(url)).timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is List && data.isNotEmpty) {
          final first = data.first;
          if (first is Map) {
            final vid = first['videoId'] as String?;
            if (vid != null && vid.length == 11) return vid;
          }
        }
      }
    } catch (e) {
      debugPrint('YT (Web) Invidious error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // MÓVIL: Scraping directo + Piped + Invidious
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchMobile(String title, String artist) async {
    final cleanTitle = _cleanTitle(title);

    final queries = [
      '$artist $cleanTitle',
      '$artist $title',
      '$artist $cleanTitle - Topic',
      '$artist $cleanTitle official audio',
    ];

    for (final query in queries) {
      // 1. YouTube Scraping directo
      final idScrape = await _searchYoutubeScrape(query);
      if (idScrape != null) {
        debugPrint('YT ✓ Scrape: $idScrape (query: "$query")');
        return idScrape;
      }

      // 2. Piped API
      final idPiped = await _searchPiped(query);
      if (idPiped != null) {
        debugPrint('YT ✓ Piped: $idPiped (query: "$query")');
        return idPiped;
      }

      // 3. Invidious API
      final idInvidious = await _searchInvidious(query);
      if (idInvidious != null) {
        debugPrint('YT ✓ Invidious: $idInvidious (query: "$query")');
        return idInvidious;
      }
    }

    debugPrint('YT ✗ No se encontró video para "$artist $title"');
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // VERIFICACIÓN DE EMBEDDABILITY (solo móvil)
  // ─────────────────────────────────────────────────────────────

  Future<bool> _isEmbeddable(String videoId) async {
    const oembedBase = 'https://www.youtube.com/oembed';
    final videoUrl = 'https://www.youtube.com/watch?v=$videoId';
    final checkUrl =
        '$oembedBase?url=${Uri.encodeComponent(videoUrl)}&format=json';

    try {
      final resp = await http
          .get(Uri.parse(checkUrl))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) return true;
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        debugPrint('YT ↷ $videoId: embedding bloqueado (${resp.statusCode})');
        return false;
      }
    } catch (_) {}
    return true;
  }

  // ─────────────────────────────────────────────────────────────
  // MÉTODO 1 (Móvil): Scraping YouTube
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchYoutubeScrape(String query) async {
    final ytSearchUrl =
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';

    final candidates = await _fetchScrapeCandidates(ytSearchUrl);
    for (final id in candidates) {
      if (await _isEmbeddable(id)) return id;
    }
    return null;
  }

  Future<List<String>> _fetchScrapeCandidates(String url) async {
    final ids = <String>[];
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/91 Mobile Safari/537.36',
      }).timeout(_timeout);

      if (resp.statusCode != 200) return ids;

      final body = resp.body;
      final seen = <String>{};
      for (final pattern in [
        RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"'),
        RegExp(r'watch\?v=([a-zA-Z0-9_-]{11})'),
      ]) {
        for (final match in pattern.allMatches(body)) {
          if (ids.length >= _maxCandidates) break;
          final id = match.group(1)!;
          if (id != 'undefined' && id.length == 11 && seen.add(id)) {
            ids.add(id);
          }
        }
        if (ids.length >= _maxCandidates) break;
      }
    } catch (e) {
      debugPrint('YT scrape error: $e');
    }
    return ids;
  }

  // ─────────────────────────────────────────────────────────────
  // MÉTODO 2 (Móvil): Piped API
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchPiped(String query) async {
    for (final filter in ['music_songs', 'videos']) {
      for (final base in _pipedInstances) {
        final pipedUrl =
            '$base/search?q=${Uri.encodeComponent(query)}&filter=$filter';
        final candidates = await _fetchPipedCandidates(pipedUrl);
        for (final id in candidates) {
          if (await _isEmbeddable(id)) return id;
        }
      }
    }
    return null;
  }

  Future<List<String>> _fetchPipedCandidates(String url) async {
    final ids = <String>[];
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (resp.statusCode != 200) return ids;

      final data = jsonDecode(resp.body);
      if (data is! Map) return ids;
      final items = data['items'] as List? ?? [];
      for (final item in items) {
        if (ids.length >= _maxCandidates) break;
        if (item is! Map) continue;
        final watchUrl = item['url'] as String? ?? '';
        final match =
            RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl) ??
                RegExp(r'/watch\?v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl);
        if (match != null) {
          ids.add(match.group(1)!);
          continue;
        }
        final vid = item['videoId'] as String?;
        if (vid != null && vid.length == 11) ids.add(vid);
      }
    } catch (e) {
      debugPrint('Piped parse error: $e');
    }
    return ids;
  }

  // ─────────────────────────────────────────────────────────────
  // MÉTODO 3 (Móvil): Invidious API
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchInvidious(String query) async {
    for (final base in _invidiousInstances) {
      final invUrl =
          '$base/api/v1/search?q=${Uri.encodeComponent(query)}&type=video&fields=videoId';
      try {
        final resp = await http
            .get(Uri.parse(invUrl), headers: {'Accept': 'application/json'})
            .timeout(_timeout);
        if (resp.statusCode != 200) continue;

        final data = jsonDecode(resp.body);
        if (data is! List || data.isEmpty) continue;
        final first = data.first;
        if (first is! Map) continue;
        final vid = first['videoId'] as String?;
        if (vid != null && vid.length == 11 && await _isEmbeddable(vid)) {
          return vid;
        }
      } catch (e) {
        debugPrint('Invidious error ($base): $e');
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  String _cleanTitle(String title) => title
      .replaceAll(RegExp(r'\s*\(feat\..*?\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\[feat\..*?\]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*ft\..*?(?=\s|$)', caseSensitive: false), '')
      .trim();
}
