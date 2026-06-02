import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Servicio de búsqueda de videos de YouTube.
///
/// Estrategia (orden de prioridad):
///   1. Piped API con corsproxy.io (garantiza CORS en web)
///   2. Piped API directa (funciona en móvil sin proxy)
///   3. YouTube scraping vía allorigins (fallback final)
class YouTubeService {
  static const _timeout = Duration(seconds: 8);

  // Piped API pública (open-source frontend de YouTube)
  static const _pipedBase = 'https://pipedapi.kavin.rocks';

  // corsproxy.io añade Access-Control-Allow-Origin: * a cualquier URL
  static String _proxied(String url) =>
      'https://corsproxy.io/?${Uri.encodeComponent(url)}';

  /// Busca el videoId de YouTube para una canción.
  Future<String?> searchVideo(String title, String artist) async {
    // Preparar variantes de búsqueda (clean elimina "feat.")
    final fullQuery = '$artist $title';
    final cleanQuery = '$artist ${_cleanTitle(title)}';

    for (final query in [cleanQuery, fullQuery]) {
      // 1. Piped + corsproxy (web) / Piped directo (móvil)
      final id = await _searchPiped(query);
      if (id != null) {
        debugPrint('YT: encontrado vía Piped: $id (query: "$query")');
        return id;
      }

      // 2. YouTube scraping vía proxy
      final id2 = await _searchYoutubeScrape(query);
      if (id2 != null) {
        debugPrint('YT: encontrado vía scrape: $id2');
        return id2;
      }
    }

    debugPrint('YT: No se encontró video para "$fullQuery"');
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // BACKEND 1: Piped API
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchPiped(String query) async {
    for (final filter in ['music_songs', 'videos']) {
      final pipedUrl =
          '$_pipedBase/search?q=${Uri.encodeComponent(query)}&filter=$filter';

      // En web usamos proxy para garantizar CORS; en móvil directo
      final urls = kIsWeb
          ? [_proxied(pipedUrl), pipedUrl]
          : [pipedUrl, _proxied(pipedUrl)];

      for (final url in urls) {
        final id = await _fetchPiped(url);
        if (id != null) return id;
      }
    }
    return null;
  }

  Future<String?> _fetchPiped(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(_timeout);

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      if (data is! Map) return null;

      final items = data['items'] as List? ?? [];
      for (final item in items) {
        if (item is! Map) continue;
        // Extraer videoId de la URL relativa /watch?v=ID
        final watchUrl = item['url'] as String? ?? '';
        final match = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl)
            ?? RegExp(r'/watch\?v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl);
        if (match != null) return match.group(1);
        // Algunos items tienen videoId directo
        final vid = item['videoId'] as String?;
        if (vid != null && vid.length == 11) return vid;
      }
    } catch (e) {
      debugPrint('YT Piped fetch error ($url): $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // BACKEND 2: Scraping YouTube vía proxy
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchYoutubeScrape(String query) async {
    final ytSearchUrl =
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';

    final urls = kIsWeb
        ? [
            // allorigins raw (respuesta directa)
            'https://api.allorigins.win/raw?url=${Uri.encodeComponent(ytSearchUrl)}',
            // corsproxy.io
            _proxied(ytSearchUrl),
          ]
        : [ytSearchUrl]; // móvil: directo sin proxy

    for (final url in urls) {
      final id = await _fetchScrape(url, isMobile: !kIsWeb && url == ytSearchUrl);
      if (id != null) return id;
    }
    return null;
  }

  Future<String?> _fetchScrape(String url, {bool isMobile = false}) async {
    try {
      final headers = isMobile
          ? {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/91 Mobile Safari/537.36',
            }
          : <String, String>{};

      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_timeout);

      if (resp.statusCode != 200) return null;

      final body = resp.body;

      // Múltiples patrones para encontrar el videoId en el HTML de YouTube
      for (final pattern in [
        RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"'),
        RegExp(r'watch\?v=([a-zA-Z0-9_-]{11})'),
        RegExp(r'"video_id":"([a-zA-Z0-9_-]{11})"'),
        RegExp(r'/embed/([a-zA-Z0-9_-]{11})'),
      ]) {
        final match = pattern.firstMatch(body);
        if (match != null) {
          final id = match.group(1)!;
          // Filtrar IDs que parecen inválidos
          if (id != 'undefined' && id.length == 11) return id;
        }
      }
    } catch (e) {
      debugPrint('YT scrape error ($url): $e');
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
