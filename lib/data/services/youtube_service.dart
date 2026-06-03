import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Servicio de búsqueda de videos de YouTube.
///
/// Estrategia optimizada para Web (PWA) y Móvil:
///
///   Por cada variante de query:
///     1. YouTube scraping vía proxy allorigins/codetabs (más rápido y fiable, ~330ms)
///     2. Piped API (fallback)
///     3. Invidious API (fallback)
///
/// Para Web (PWA), todas las llamadas externas usan el proxy 'allorigins' con su endpoint
/// JSON (/get) para evitar que Cloudflare bloquee la petición por CORS y cabeceras de origen.
/// El check oEmbed se desactiva en Web porque los proxies de CORS añaden lentitud e
/// inestabilidad; el reproductor iFrame ya maneja los errores si un vídeo no es reproducible.
class YouTubeService {
  static const _timeout = Duration(seconds: 8);

  /// Máximo de candidatos a evaluar por búsqueda.
  static const _maxCandidates = 5;

  // Instancias públicas de Piped
  static const _pipedInstances = [
    'https://pipedapi.in.projectsegfau.lt',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.kavin.rocks',
  ];

  // Instancias públicas de Invidious
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
    final cleanTitle = _cleanTitle(title);

    final queries = [
      '$artist $cleanTitle',
      '$artist $title',
      '$artist $cleanTitle - Topic',
      '$artist $cleanTitle official audio',
    ];

    for (final query in queries) {
      // 1. YouTube Scraping (Es el método más rápido y fiable, funciona en ~330ms)
      final idScrape = await _searchYoutubeScrape(query);
      if (idScrape != null) {
        debugPrint('YT ✓ Scrape: $idScrape (query: "$query")');
        return idScrape;
      }

      // 2. Piped API (Instancias redundantes)
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
  // HELPER DE CONSULTA HTTP CON PROXY AUTOMÁTICO (CORS BYPASS)
  // ─────────────────────────────────────────────────────────────

  /// Realiza la consulta HTTP gestionando de forma transparente las políticas CORS.
  /// En Web: utiliza el proxy JSON allorigins (o fallback codetabs).
  /// En Móvil: realiza la petición directa.
  Future<String?> _fetchBody(String url, {Map<String, String>? headers}) async {
    try {
      if (!kIsWeb) {
        // Móvil: directo sin proxy
        final resp = await http.get(Uri.parse(url), headers: headers).timeout(_timeout);
        if (resp.statusCode == 200) return resp.body;
        return null;
      }

      // Web: Proxy principal -> allorigins /get (retorna JSON para saltar Cloudflare browser integrity)
      final proxyUrl = 'https://api.allorigins.win/get?url=${Uri.encodeComponent(url)}';
      final resp = await http.get(Uri.parse(proxyUrl)).timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['contents'] as String?;
      }

      // Web: Proxy de soporte -> codetabs
      final backupUrl = 'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(url)}';
      final respBackup = await http.get(Uri.parse(backupUrl)).timeout(_timeout);
      if (respBackup.statusCode == 200) {
        return respBackup.body;
      }
    } catch (e) {
      debugPrint('Error de red/proxy al consultar ($url): $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // VERIFICACIÓN DE EMBEDDABILITY (solo para móvil)
  // ─────────────────────────────────────────────────────────────

  /// Comprueba si el vídeo permite reproducción embebida (solo móvil).
  /// En Web siempre retorna true para evitar cuellos de botella por CORS.
  Future<bool> _isEmbeddable(String videoId) async {
    if (kIsWeb) return true;

    const oembedBase = 'https://www.youtube.com/oembed';
    final videoUrl = 'https://www.youtube.com/watch?v=$videoId';
    final checkUrl = '$oembedBase?url=${Uri.encodeComponent(videoUrl)}&format=json';

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
  // METODO 1: Scraping YouTube
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
    final headers = !kIsWeb
        ? {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/91 Mobile Safari/537.36',
          }
        : <String, String>{};

    final body = await _fetchBody(url, headers: headers);
    if (body == null || body.isEmpty) return ids;

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
    return ids;
  }

  // ─────────────────────────────────────────────────────────────
  // METODO 2: Piped API
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchPiped(String query) async {
    for (final filter in ['music_songs', 'videos']) {
      for (final base in _pipedInstances) {
        final pipedUrl =
            '$base/search?q=${Uri.encodeComponent(query)}&filter=$filter';

        final candidates = await _fetchPipedCandidates(pipedUrl);
        if (candidates.isEmpty) continue;

        for (final id in candidates) {
          if (await _isEmbeddable(id)) return id;
        }
      }
    }
    return null;
  }

  Future<List<String>> _fetchPipedCandidates(String url) async {
    final ids = <String>[];
    final body = await _fetchBody(url, headers: {'Accept': 'application/json'});
    if (body == null || body.isEmpty) return ids;

    try {
      final data = jsonDecode(body);
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
  // METODO 3: Invidious API
  // ─────────────────────────────────────────────────────────────

  Future<String?> _searchInvidious(String query) async {
    for (final base in _invidiousInstances) {
      final invUrl =
          '$base/api/v1/search?q=${Uri.encodeComponent(query)}&type=video&fields=videoId';

      final id = await _fetchInvidious(invUrl);
      if (id != null && await _isEmbeddable(id)) return id;
    }
    return null;
  }

  Future<String?> _fetchInvidious(String url) async {
    final body = await _fetchBody(url, headers: {'Accept': 'application/json'});
    if (body == null || body.isEmpty) return null;

    try {
      final data = jsonDecode(body);
      if (data is! List || data.isEmpty) return null;

      final first = data.first;
      if (first is! Map) return null;

      final vid = first['videoId'] as String?;
      if (vid != null && vid.length == 11) return vid;
    } catch (e) {
      debugPrint('Invidious parse error: $e');
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
