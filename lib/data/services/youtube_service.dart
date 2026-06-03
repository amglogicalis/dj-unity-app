import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Servicio de búsqueda de videos de YouTube.
///
/// Estrategia para maximizar la cobertura:
///
///   Por cada variante de query (clean → full → topic → official audio):
///     1. Piped API  (3 instancias públicas de fallback)
///     2. Invidious  (frontend alternativo de YouTube, completamente distinto)
///     3. YouTube scraping vía proxy
///
/// En MÓVIL: cada candidato se verifica con oEmbed antes de devolverlo,
///   para saltar vídeos con embedding bloqueado.
/// En WEB:   se omite el check oEmbed (el proxy lo hace poco fiable y lento);
///   el IFrame del reproductor ya maneja el error si el vídeo no es embeddable.
class YouTubeService {
  static const _timeout = Duration(seconds: 8);

  /// Máximo de candidatos a evaluar por búsqueda antes de pasar al siguiente query.
  static const _maxCandidates = 5;

  // ── Instancias Piped (se prueban en orden hasta que una responda) ──────────
  static const _pipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.in.projectsegfau.lt',
  ];

  // ── Instancias Invidious (frontend YT alternativo con API propia) ──────────
  static const _invidiousInstances = [
    'https://invidious.slipfox.xyz',
    'https://iv.ggtyler.dev',
    'https://invidious.privacyredirect.com',
  ];

  // corsproxy.io añade Access-Control-Allow-Origin: * a cualquier URL
  static String _proxied(String url) =>
      'https://corsproxy.io/?${Uri.encodeComponent(url)}';

  // allorigins como proxy alternativo
  static String _allorigins(String url) =>
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';

  // ─────────────────────────────────────────────────────────────
  // PUNTO DE ENTRADA PÚBLICO
  // ─────────────────────────────────────────────────────────────

  /// Busca el videoId de YouTube para una canción.
  ///
  /// Prueba en orden:
  ///   1. Query limpia  (sin "feat.")
  ///   2. Query completa (con feat.)
  ///   3. Query con "- Topic"         → canales YouTube Music
  ///   4. Query con "official audio"  → audios oficiales
  ///
  /// Para cada query, intenta: Piped → Invidious → Scraping
  Future<String?> searchVideo(String title, String artist) async {
    final cleanTitle = _cleanTitle(title);

    final queries = [
      '$artist $cleanTitle',
      '$artist $title',
      '$artist $cleanTitle - Topic',
      '$artist $cleanTitle official audio',
    ];

    for (final query in queries) {
      // Backend 1: Piped API (múltiples instancias)
      final id1 = await _searchPiped(query);
      if (id1 != null) {
        debugPrint('YT ✓ Piped: $id1 (query: "$query")');
        return id1;
      }

      // Backend 2: Invidious API
      final id2 = await _searchInvidious(query);
      if (id2 != null) {
        debugPrint('YT ✓ Invidious: $id2 (query: "$query")');
        return id2;
      }

      // Backend 3: Scraping YouTube vía proxy
      final id3 = await _searchYoutubeScrape(query);
      if (id3 != null) {
        debugPrint('YT ✓ Scrape: $id3 (query: "$query")');
        return id3;
      }
    }

    debugPrint('YT ✗ No se encontró video para "$artist $title"');
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // VERIFICACIÓN DE EMBEDDABILITY (solo móvil — sin CORS)
  // ─────────────────────────────────────────────────────────────

  /// En web siempre devuelve true (el check vía proxy es poco fiable y lento).
  /// En móvil consulta el endpoint oEmbed de YouTube directamente.
  Future<bool> _isEmbeddable(String videoId) async {
    // En web omitimos el check: el IFrame player gestiona el error directamente
    if (kIsWeb) return true;

    const oembedBase = 'https://www.youtube.com/oembed';
    final videoUrl = 'https://www.youtube.com/watch?v=$videoId';
    final checkUrl = '$oembedBase?url=${Uri.encodeComponent(videoUrl)}&format=json';

    try {
      final resp = await http
          .get(Uri.parse(checkUrl))
          .timeout(const Duration(seconds: 5));
      // 200 → embeddable. 401/403 → bloqueado. Cualquier otro → asumir embeddable.
      if (resp.statusCode == 200) return true;
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        debugPrint('YT ↷ $videoId: embedding bloqueado (${resp.statusCode})');
        return false;
      }
    } catch (_) {
      // Timeout o error de red → no podemos saber → asumir embeddable
    }
    return true;
  }

  // ─────────────────────────────────────────────────────────────
  // BACKEND 1: Piped API (3 instancias de fallback)
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchPiped(String query) async {
    for (final filter in ['music_songs', 'videos']) {
      for (final base in _pipedInstances) {
        final pipedUrl =
            '$base/search?q=${Uri.encodeComponent(query)}&filter=$filter';

        // En web: proxy primero (CORS); en móvil: directo primero
        final urls = kIsWeb
            ? [_proxied(pipedUrl), _allorigins(pipedUrl)]
            : [pipedUrl, _proxied(pipedUrl)];

        for (final url in urls) {
          final candidates = await _fetchPipedCandidates(url);
          if (candidates.isEmpty) continue;

          for (final id in candidates) {
            if (await _isEmbeddable(id)) return id;
          }
        }
      }
    }
    return null;
  }

  /// Devuelve hasta [_maxCandidates] IDs del resultado de Piped.
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

        // Extraer videoId de la URL relativa /watch?v=ID
        final watchUrl = item['url'] as String? ?? '';
        final match =
            RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl) ??
            RegExp(r'/watch\?v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl);
        if (match != null) {
          ids.add(match.group(1)!);
          continue;
        }
        // Algunos items tienen videoId directo
        final vid = item['videoId'] as String?;
        if (vid != null && vid.length == 11) ids.add(vid);
      }
    } catch (e) {
      debugPrint('YT Piped fetch error ($url): $e');
    }
    return ids;
  }

  // ─────────────────────────────────────────────────────────────
  // BACKEND 2: Invidious API (frontend YT alternativo)
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchInvidious(String query) async {
    for (final base in _invidiousInstances) {
      final invUrl =
          '$base/api/v1/search?q=${Uri.encodeComponent(query)}&type=video&fields=videoId';

      // En web necesitamos proxy por CORS
      final urls = kIsWeb
          ? [_proxied(invUrl), _allorigins(invUrl)]
          : [invUrl];

      for (final url in urls) {
        final id = await _fetchInvidious(url);
        if (id != null && await _isEmbeddable(id)) return id;
      }
    }
    return null;
  }

  Future<String?> _fetchInvidious(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(_timeout);

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      if (data is! List || data.isEmpty) return null;

      final first = data.first;
      if (first is! Map) return null;

      final vid = first['videoId'] as String?;
      if (vid != null && vid.length == 11) return vid;
    } catch (e) {
      debugPrint('YT Invidious fetch error ($url): $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // BACKEND 3: Scraping YouTube vía proxy
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchYoutubeScrape(String query) async {
    final ytSearchUrl =
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';

    final urls = kIsWeb
        ? [
            _allorigins(ytSearchUrl),
            _proxied(ytSearchUrl),
          ]
        : [ytSearchUrl]; // móvil: directo sin proxy

    for (final url in urls) {
      final candidates = await _fetchScrapeCandidates(
          url, isMobile: !kIsWeb && url == ytSearchUrl);
      for (final id in candidates) {
        if (await _isEmbeddable(id)) return id;
      }
    }
    return null;
  }

  /// Devuelve hasta [_maxCandidates] IDs extraídos del HTML de YouTube.
  Future<List<String>> _fetchScrapeCandidates(String url,
      {bool isMobile = false}) async {
    final ids = <String>[];
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

      if (resp.statusCode != 200) return ids;

      final body = resp.body;
      final seen = <String>{};

      for (final pattern in [
        RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"'),
        RegExp(r'watch\?v=([a-zA-Z0-9_-]{11})'),
        RegExp(r'"video_id":"([a-zA-Z0-9_-]{11})"'),
        RegExp(r'/embed/([a-zA-Z0-9_-]{11})'),
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
      debugPrint('YT scrape error ($url): $e');
    }
    return ids;
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
