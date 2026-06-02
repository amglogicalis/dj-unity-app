/// Modos de reproducción disponibles para la sala del Host.
enum RoomMode {
  /// Modo 1: Spotify Free — abre la canción en Spotify via deep link.
  /// El DJ le da play manualmente en Spotify. Sin cuenta Premium necesaria.
  spotifyFree,

  /// Modo 2: Spotify Premium — control total via Spotify Web API con OAuth.
  /// Play, pause, skip, añadir a cola directamente desde la app.
  /// Requiere cuenta Spotify Premium del Host.
  spotifyPremium,

  /// Modo 3: YouTube integrado — reproductor YouTube iFrame embebido en la app.
  /// Sin dependencia de cuenta ni app externa. Control total desde la app.
  youtubeIntegrated,
}

extension RoomModeExtension on RoomMode {
  String get firestoreKey {
    switch (this) {
      case RoomMode.spotifyFree:
        return 'spotify_free';
      case RoomMode.spotifyPremium:
        return 'spotify_premium';
      case RoomMode.youtubeIntegrated:
        return 'youtube_integrated';
    }
  }

  String get displayName {
    switch (this) {
      case RoomMode.spotifyFree:
        return 'Spotify Free';
      case RoomMode.spotifyPremium:
        return 'Spotify Premium';
      case RoomMode.youtubeIntegrated:
        return 'YouTube Integrado';
    }
  }

  static RoomMode fromFirestoreKey(String key) {
    switch (key) {
      case 'spotify_premium':
        return RoomMode.spotifyPremium;
      case 'youtube_integrated':
        return RoomMode.youtubeIntegrated;
      default:
        return RoomMode.spotifyFree;
    }
  }
}
