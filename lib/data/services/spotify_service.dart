import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Servicio encargado de gestionar la resolución de canciones en la API Web de Spotify gratis.
class SpotifyService {
  // Credenciales de tu app de Spotify Developer (developer.spotify.com)
  // NOTA: Registra tu app en el panel de desarrollador de Spotify para obtener tus claves gratuitas.
  static const String clientId = 'YOUR_SPOTIFY_CLIENT_ID';
  static const String clientSecret = 'YOUR_SPOTIFY_CLIENT_SECRET';

  String? _searchToken;

  /// Obtiene un Token de Acceso público mediante el flujo "Client Credentials Flow" de Spotify.
  /// Este flujo es 100% gratuito y no requiere cuentas de usuario ni licencias Premium.
  Future<String?> getSearchToken() async {
    if (_searchToken != null) return _searchToken;

    if (clientId == 'YOUR_SPOTIFY_CLIENT_ID' || clientSecret == 'YOUR_SPOTIFY_CLIENT_SECRET') {
      debugPrint('SpotifyService: [Nota] Las credenciales son las por defecto. Usando el fallback de búsqueda directa sin API.');
      return null;
    }

    try {
      debugPrint('SpotifyService: Obteniendo token de cliente...');
      final authString = base64Encode(utf8.encode('$clientId:$clientSecret'));
      
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $authString',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'client_credentials',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _searchToken = data['access_token'] as String?;
        debugPrint('SpotifyService: Token obtenido con éxito.');
        return _searchToken;
      } else {
        debugPrint('SpotifyService: Fallo al obtener token. Código ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('SpotifyService: Excepción obteniendo token de cliente: $e');
      return null;
    }
  }

  /// Realiza una búsqueda silenciosa en el catálogo de Spotify usando el track y el artista.
  /// Retorna el ID de Spotify del tema (ej. "4PTG3Z6ehGkBF3sI7WvqRq").
  Future<String?> searchTrack(String title, String artist) async {
    final token = await getSearchToken();
    if (token == null) {
      debugPrint('SpotifyService: No se pudo obtener un token de búsqueda.');
      return null;
    }

    try {
      final query = 'track:$title artist:$artist';
      final searchUrl = Uri.parse(
        'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=1',
      );

      debugPrint('SpotifyService: Buscando track en Spotify API: $query');
      final response = await http.get(
        searchUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tracks = data['tracks'] as Map<String, dynamic>?;
        final items = tracks?['items'] as List<dynamic>? ?? [];

        if (items.isNotEmpty) {
          final firstTrack = items.first as Map<String, dynamic>;
          final trackId = firstTrack['id'] as String? ?? '';
          if (trackId.isNotEmpty) {
            debugPrint('SpotifyService: Track resuelto exitosamente: $trackId');
            return trackId;
          }
        }
        debugPrint('SpotifyService: No se encontró ningún track coincidente en Spotify.');
        return null;
      } else {
        debugPrint('SpotifyService: Error en búsqueda. API respondió con código ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('SpotifyService: Excepción durante la búsqueda en Spotify: $e');
      return null;
    }
  }
}
