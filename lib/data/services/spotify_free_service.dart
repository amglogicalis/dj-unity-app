import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Servicio para el Modo 1 (Spotify Free).
///
/// Estrategia por plataforma:
///   • Web  → Abre directamente la búsqueda en open.spotify.com (sin API, sin CORS).
///   • Móvil → Intenta resolver el Track ID exacto via API; si falla, abre búsqueda.
class SpotifyFreeService {
  static const String _clientId = '1621681a987c4e62ad51444c77df319f';
  static const String _clientSecret = '614e6b4a66644b4e837c8235a0612369';

  String? _cachedToken;
  DateTime? _tokenExpiry;

  // ─────────────────────────────────────────────────────────────
  // PUNTO DE ENTRADA PRINCIPAL
  // ─────────────────────────────────────────────────────────────

  /// Busca la canción y la abre en Spotify.
  /// En web siempre usa la URL de búsqueda (evita CORS).
  /// En móvil intenta el Track ID exacto vía API, con fallback a búsqueda.
  Future<bool> searchAndOpen(String title, String artist) async {
    if (kIsWeb) {
      // Web: abrir búsqueda directamente, sin API ni CORS
      return _openSpotifySearch(title, artist);
    } else {
      // Móvil: intentar Track ID exacto
      final trackId = await searchTrackId(title, artist);
      if (trackId != null && trackId.isNotEmpty) {
        return _openTrackUri(trackId);
      }
      // Fallback: búsqueda
      return _openSpotifySearch(title, artist);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BÚSQUEDA VIA API (solo móvil)
  // ─────────────────────────────────────────────────────────────

  Future<String?> searchTrackId(String title, String artist) async {
    final token = await _getToken();
    if (token == null) return null;

    // Limpiar el título: quitar "(feat. ...)" para mayor precisión
    final cleanTitle = _cleanTitle(title);

    // Intentar varias estrategias de búsqueda
    final queries = [
      'track:"$cleanTitle" artist:"$artist"',
      '$cleanTitle $artist',
      '$title $artist',
    ];

    for (final q in queries) {
      final id = await _querySpotify(q, token);
      if (id != null) return id;
    }
    return null;
  }

  Future<String?> _querySpotify(String query, String token) async {
    try {
      final url = Uri.parse(
        'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=3',
      );
      final resp = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items =
            (data['tracks']?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (items.isNotEmpty) return items.first['id'] as String?;
      }
    } catch (e) {
      debugPrint('SpotifyFreeService: Error en búsqueda: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // TOKEN (solo para móvil)
  // ─────────────────────────────────────────────────────────────

  Future<String?> _getToken() async {
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken;
    }
    try {
      final auth = base64Encode(utf8.encode('$_clientId:$_clientSecret'));
      final resp = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $auth',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _cachedToken = data['access_token'] as String?;
        final exp = data['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: exp - 60));
        return _cachedToken;
      }
    } catch (e) {
      debugPrint('SpotifyFreeService: Error obteniendo token: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // ABRIR URLS
  // ─────────────────────────────────────────────────────────────

  /// Abre la búsqueda en Spotify web (misma pestaña en web, app/navegador en móvil).
  Future<bool> _openSpotifySearch(String title, String artist) async {
    final query = Uri.encodeComponent('$title $artist');
    final uri = Uri.parse('https://open.spotify.com/search/$query');

    if (kIsWeb) {
      // '_spotify': crea la pestaña la primera vez, la reutiliza las siguientes
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, webOnlyWindowName: '_spotify');
      }
    } else {
      // Móvil: intentar abrir app de Spotify primero
      final nativeSearchUri =
          Uri.parse('spotify:search:${Uri.encodeComponent('$title $artist')}');
      if (await canLaunchUrl(nativeSearchUri)) {
        return launchUrl(nativeSearchUri);
      }
      // Fallback: abrir en el navegador externo (sin cerrar la app Flutter)
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    return false;
  }

  /// Abre un track concreto en la app de Spotify (solo móvil).
  Future<bool> _openTrackUri(String trackId) async {
    final nativeUri = Uri.parse('spotify:track:$trackId');
    if (await canLaunchUrl(nativeUri)) {
      return launchUrl(nativeUri);
    }
    final webUri = Uri.parse('https://open.spotify.com/track/$trackId');
    if (await canLaunchUrl(webUri)) {
      return launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  /// Limpia el título eliminando "(feat. ...)" para búsquedas más precisas.
  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*\(feat\..*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[feat\..*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*ft\..*?(?=\s|$)', caseSensitive: false), '')
        .trim();
  }
}
