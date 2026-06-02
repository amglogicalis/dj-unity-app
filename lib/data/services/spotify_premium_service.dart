import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Servicio para el Modo 2 (Spotify Premium).
///
/// Implementa el flujo OAuth 2.0 PKCE de Spotify y expone métodos de
/// control total de reproducción via Spotify Web API:
///   play, pause, skip, añadir a cola, seek, volumen.
///
/// REQUISITO: El Host debe tener cuenta Spotify Premium activa.
class SpotifyPremiumService {
  // Configura en https://developer.spotify.com/dashboard
  static const String _clientId = '1621681a987c4e62ad51444c77df319f';
  // Redirect URI registrada en la Spotify App (debe coincidir exactamente)
  static const String _redirectUri = 'hybridmusicroom://callback';
  // Scopes necesarios para control de reproducción
  static const String _scopes =
      'user-read-playback-state user-modify-playback-state user-read-currently-playing';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;

  bool get isAuthenticated =>
      _accessToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!);

  /// Inicia el flujo de autenticación OAuth 2.0 abriendo el navegador.
  Future<void> authenticate() async {
    final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': _clientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': _scopes,
      'show_dialog': 'true',
    });

    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('SpotifyPremiumService: No se pudo abrir la URL de autenticación.');
    }
  }

  /// Maneja el callback OAuth con el código de autorización recibido.
  Future<bool> handleAuthCallback(String code) async {
    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
          'client_id': _clientId,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        _refreshToken = data['refresh_token'] as String?;
        final expiresIn = data['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        debugPrint('SpotifyPremiumService: Autenticación exitosa.');
        return true;
      }
    } catch (e) {
      debugPrint('SpotifyPremiumService: Error en callback OAuth: $e');
    }
    return false;
  }

  /// Refresca el token de acceso usando el refresh token.
  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;
    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
          'client_id': _clientId,
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        final expiresIn = data['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        return true;
      }
    } catch (e) {
      debugPrint('SpotifyPremiumService: Error al refrescar token: $e');
    }
    return false;
  }

  /// Obtiene un token válido, refrescándolo si es necesario.
  Future<String?> _getValidToken() async {
    if (_accessToken == null) return null;
    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!)) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) return null;
    }
    return _accessToken;
  }

  /// Ejecuta una petición autenticada a la Spotify Web API.
  Future<http.Response?> _apiCall(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    final token = await _getValidToken();
    if (token == null) {
      debugPrint('SpotifyPremiumService: No hay token válido. Autenticación necesaria.');
      return null;
    }

    final uri = Uri.https(
      'api.spotify.com',
      endpoint,
      queryParams,
    );

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    try {
      switch (method.toUpperCase()) {
        case 'PUT':
          return await http
              .put(uri, headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 8));
        case 'POST':
          return await http
              .post(uri, headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 8));
        case 'GET':
          return await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 8));
        default:
          return null;
      }
    } catch (e) {
      debugPrint('SpotifyPremiumService: Error en API call $method $endpoint: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // CONTROL DE REPRODUCCIÓN
  // ─────────────────────────────────────────────

  /// Busca un track por título y artista y lo reproduce inmediatamente.
  Future<bool> playTrack(String spotifyUri) async {
    final response = await _apiCall(
      'PUT',
      '/v1/me/player/play',
      body: {'uris': ['spotify:track:$spotifyUri']},
    );
    return _isSuccess(response);
  }

  /// Pausa la reproducción actual.
  Future<bool> pause() async {
    final response = await _apiCall('PUT', '/v1/me/player/pause');
    return _isSuccess(response);
  }

  /// Reanuda la reproducción.
  Future<bool> resume() async {
    final response = await _apiCall('PUT', '/v1/me/player/play');
    return _isSuccess(response);
  }

  /// Salta a la siguiente canción.
  Future<bool> skipNext() async {
    final response = await _apiCall('POST', '/v1/me/player/next');
    return _isSuccess(response);
  }

  /// Añade un track a la cola de Spotify (sin interrumpir la canción actual).
  Future<bool> addToQueue(String spotifyTrackId) async {
    final response = await _apiCall(
      'POST',
      '/v1/me/player/queue',
      queryParams: {'uri': 'spotify:track:$spotifyTrackId'},
    );
    return _isSuccess(response);
  }

  /// Salta a la posición indicada en la canción actual (en ms).
  Future<bool> seek(Duration position) async {
    final response = await _apiCall(
      'PUT',
      '/v1/me/player/seek',
      queryParams: {'position_ms': '${position.inMilliseconds}'},
    );
    return _isSuccess(response);
  }

  /// Busca el Spotify Track ID dado un título y artista.
  Future<String?> searchTrackId(String title, String artist) async {
    final token = await _getValidToken();
    if (token == null) return null;

    final queries = [
      'track:"$title" artist:"$artist"',
      '$title $artist',
    ];

    for (final query in queries) {
      final url = Uri.https('api.spotify.com', '/v1/search', {
        'q': query,
        'type': 'track',
        'limit': '3',
      });

      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['tracks']?['items'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        if (items.isNotEmpty) {
          return items.first['id'] as String?;
        }
      }
    }
    return null;
  }

  /// Obtiene el estado actual de la reproducción de Spotify.
  Future<Map<String, dynamic>?> getPlaybackState() async {
    final response = await _apiCall('GET', '/v1/me/player');
    if (response != null && response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  bool _isSuccess(http.Response? response) {
    if (response == null) return false;
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  /// Cierra sesión limpiando los tokens.
  void logout() {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
  }
}
