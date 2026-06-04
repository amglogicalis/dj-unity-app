import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:hybrid_music_room/data/models/room_mode.dart';
import 'package:hybrid_music_room/data/services/spotify_free_service.dart';
import 'package:hybrid_music_room/data/services/spotify_premium_service.dart';
import 'package:hybrid_music_room/data/services/youtube_service.dart';

/// Pantalla principal del Host (DJ).
/// Soporta 3 modos: Spotify Free, Spotify Premium y YouTube Integrado.
class HostRoomPage extends StatefulWidget {
  const HostRoomPage({super.key});

  @override
  State<HostRoomPage> createState() => _HostRoomPageState();
}

class _HostRoomPageState extends State<HostRoomPage> {
  // ── Modo de sala ──────────────────────────────────────────────
  RoomMode _mode = RoomMode.spotifyFree; // default, sobrescrito en addPostFrameCallback

  // ── Estado general ────────────────────────────────────────────
  String _pin = '';
  bool _isPlaying = false;
  String? _currentPlayingDocId;
  Timer? _playbackTimer;

  // ── Animación ecualizador ─────────────────────────────────────
  final Random _random = Random();
  final List<double> _waveHeights = List.generate(15, (_) => 4.0);
  int _waveUpdateCounter = 0;

  // ── Firestore ─────────────────────────────────────────────────
  late Stream<QuerySnapshot> _playlistStream;

  // ── Progreso (sin reconstruir toda la UI) ─────────────────────
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);
  Duration _totalDuration = Duration.zero;

  // ── Servicios ─────────────────────────────────────────────────
  final SpotifyFreeService _spotifyFree = SpotifyFreeService();
  final SpotifyPremiumService _spotifyPremium = SpotifyPremiumService();
  final YouTubeService _youtubeService = YouTubeService();

  // ── Modo YouTube: controlador iFrame ─────────────────────────
  YoutubePlayerController? _ytController;
  StreamSubscription? _ytStateSubscription;
  StreamSubscription? _ytValueSubscription;
  String? _currentYtVideoId;

  // ── Seek: flag + target para liberar solo cuando el stream confirma ───────
  bool _isSeeking = false;
  double? _seekTarget;        // posición buscada (segundos)
  Timer? _seekFailsafeTimer; // libera el bloqueo si el stream tarda mucho

  // ── Modo Spotify Premium: polling de estado ───────────────────
  Timer? _spotifyPollingTimer;
  bool _spotifyAuthInProgress = false;

  // ── YouTube: flag de player listo ───────────────────────
  bool _ytPlayerReady = false;
  bool _ytSearching = false;

  // ── DJ: añadir canciones a la cola ────────────────────────
  final TextEditingController _djSearchController = TextEditingController();
  List<Map<String, String>> _djSearchResults = [];
  bool _djIsSearching = false;
  Timer? _djDebounce;

  // ───────────────────────────────────────────────────────────────
  // DJ: AÑADIR CANCIONES A LA COLA
  // ───────────────────────────────────────────────────────────────

  /// Abre el bottom sheet para que el DJ busque y añada canciones a la cola.
  void _showAddSongBottomSheet() {
    _djSearchController.clear();
    _djSearchResults = [];
    _djIsSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Búsqueda con debounce de 600ms
            void onQueryChanged(String q) {
              _djDebounce?.cancel();
              _djDebounce = Timer(const Duration(milliseconds: 600), () async {
                final query = q.trim();
                if (query.isEmpty) {
                  setSheetState(() {
                    _djSearchResults = [];
                    _djIsSearching = false;
                  });
                  return;
                }
                setSheetState(() => _djIsSearching = true);

                try {
                  final List<Map<String, String>> results = await _djSearchMusicBrainz(query);
                  if (ctx.mounted) {
                    setSheetState(() {
                      _djSearchResults = results;
                      _djIsSearching = false;
                    });
                  }
                } catch (e) {
                  debugPrint('DJ search error: $e');
                  if (ctx.mounted) setSheetState(() => _djIsSearching = false);
                }
              });
            }

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F11),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Título
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _modeAccentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.add_rounded,
                              color: _modeAccentColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Añadir canción',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campo de búsqueda
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _djSearchController,
                      autofocus: true,
                      onChanged: onQueryChanged,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar canción o artista...',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3)),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: Colors.white.withValues(alpha: 0.5)),
                        suffixIcon: _djIsSearching
                            ? Padding(
                                padding: const EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: _modeAccentColor,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              BorderSide(color: _modeAccentColor, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Resultados
                  Expanded(
                    child: _djSearchResults.isEmpty && !_djIsSearching
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.queue_music_rounded,
                                    size: 52,
                                    color:
                                        Colors.white.withValues(alpha: 0.1)),
                                const SizedBox(height: 12),
                                Text(
                                  'Escribe para buscar',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.4),
                                      fontSize: 15),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            itemCount: _djSearchResults.length,
                            itemBuilder: (_, i) {
                              final song = _djSearchResults[i];
                              final thumb = song['thumbnailUrl'] ?? '';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.05)),
                                ),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: thumb.isNotEmpty
                                        ? Image.network(
                                            thumb,
                                            width: 55,
                                            height: 40,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (_, __, ___) =>
                                                    _thumbPlaceholder(),
                                          )
                                        : _thumbPlaceholder(),
                                  ),
                                  title: Text(
                                    song['title'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    song['artist'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.6)),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.add_circle_rounded,
                                        color: _modeAccentColor, size: 28),
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      await _djAddSongToQueue(song);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Padding para el teclado
                  SizedBox(
                      height: MediaQuery.of(ctx).viewInsets.bottom + 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Busca canciones usando MusicBrainz (catálogo completo).
  /// Misma lógica que guest_room_page.dart para consistencia.
  Future<List<Map<String, String>>> _djSearchMusicBrainz(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final mbUrl =
        'https://musicbrainz.org/ws/2/recording?query=$encodedQuery&fmt=json&limit=25';

    http.Response response;
    if (kIsWeb) {
      final proxiedUrl = Uri.parse(
        'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(mbUrl)}',
      );
      response = await http.get(proxiedUrl).timeout(const Duration(seconds: 12));
    } else {
      response = await http.get(
        Uri.parse(mbUrl),
        headers: {
          'User-Agent': 'DemocraticDJ/1.0 (https://democratic-dj-fe97d.web.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
    }

    if (response.statusCode != 200) {
      throw Exception('MusicBrainz status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final recordings = data['recordings'] as List<dynamic>? ?? [];
    final results = <Map<String, String>>[];
    final seen = <String>{};

    for (final recording in recordings) {
      if (recording is! Map<String, dynamic>) continue;
      final score = recording['score'] as int? ?? 0;
      if (score < 30) continue;

      final title = recording['title'] as String? ?? '';
      if (title.isEmpty) continue;

      final artistCredits = recording['artist-credit'] as List<dynamic>? ?? [];
      final artistParts = <String>[];
      for (final credit in artistCredits) {
        if (credit is Map<String, dynamic>) {
          final artist = credit['artist'] as Map<String, dynamic>?;
          final name = artist?['name'] as String?;
          if (name != null && name.isNotEmpty) artistParts.add(name);
          final joinPhrase = credit['joinphrase'] as String? ?? '';
          if (joinPhrase.isNotEmpty && artistParts.isNotEmpty) {
            artistParts.last = artistParts.last + joinPhrase;
          }
        }
      }
      final artistName = artistParts.join(' ').trim();
      if (artistName.isEmpty) continue;

      final key = '${title.toLowerCase()}|${artistName.toLowerCase()}';
      if (seen.contains(key)) continue;
      seen.add(key);

      final releases = recording['releases'] as List<dynamic>? ?? [];
      String thumbnailUrl = '';
      if (releases.isNotEmpty && releases.first is Map<String, dynamic>) {
        final releaseId =
            (releases.first as Map<String, dynamic>)['id'] as String? ?? '';
        if (releaseId.isNotEmpty) {
          thumbnailUrl =
              'https://coverartarchive.org/release/$releaseId/front-250';
        }
      }

      results.add({
        'title': title,
        'artist': artistName,
        'thumbnailUrl': thumbnailUrl,
        'mbid': recording['id'] as String? ?? '',
      });
    }
    return results;
  }

  /// Añade la canción seleccionada a la cola de Firestore del DJ.
  Future<void> _djAddSongToQueue(Map<String, String> song) async {
    if (_pin.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(_pin)
          .collection('playlist')
          .add({
        'title': song['title'] ?? '',
        'artist': song['artist'] ?? '',
        'platform': 'musicbrainz',
        'videoOrTrackId': song['mbid'] ?? '',
        'thumbnailUrl': song['thumbnailUrl'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _showInfo('"${song['title']}" añadida a la cola 🎧');
    } catch (e) {
      _showError('Error al añadir canción: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _generatePin();
    _startWaveTimer();
  }


  @override
  void dispose() {
    _playbackTimer?.cancel();
    _spotifyPollingTimer?.cancel();
    _seekFailsafeTimer?.cancel();
    _ytStateSubscription?.cancel();
    _ytValueSubscription?.cancel();
    _ytController?.close();
    _progressNotifier.dispose();
    _djSearchController.dispose();
    _djDebounce?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // INICIALIZACIÓN
  // ─────────────────────────────────────────────────────────────

  void _generatePin() {
    // Leer el modo del argumento de navegación
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      _mode = (args is RoomMode) ? args : RoomMode.spotifyFree;

      final random = Random();
      final pinNum = random.nextInt(9000) + 1000;
      final pinStr = pinNum.toString();

      _playlistStream = FirebaseFirestore.instance
          .collection('rooms')
          .doc(pinStr)
          .collection('playlist')
          .orderBy('createdAt', descending: false)
          .snapshots();

      setState(() => _pin = pinStr);
      _createRoomInFirestore(pinStr);

      // Inicializar el servicio según el modo
      if (_mode == RoomMode.youtubeIntegrated) {
        _initYoutubePlayer();
      } else if (_mode == RoomMode.spotifyPremium) {
        _initSpotifyPremium();
      }
    });
  }

  Future<void> _createRoomInFirestore(String pin) async {
    await FirebaseFirestore.instance.collection('rooms').doc(pin).set({
      'hostId': 'host_device_id_real_dj',
      'isPlaying': false,
      'currentPlatform': _mode.firestoreKey,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _startWaveTimer() {
    _playbackTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_isPlaying && _currentPlayingDocId != null) {
        setState(() {
          _waveUpdateCounter++;
          if (_waveUpdateCounter >= 3) {
            _waveUpdateCounter = 0;
            for (int i = 0; i < _waveHeights.length; i++) {
              _waveHeights[i] = _random.nextDouble() * 35.0 + 5.0;
            }
          }
        });
      } else {
        if (_waveHeights.any((h) => h != 4.0)) {
          setState(() => _waveHeights.fillRange(0, _waveHeights.length, 4.0));
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // MODO 3: YouTube iFrame
  // ─────────────────────────────────────────────────────────────

  void _initYoutubePlayer() {
    _ytController = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showVideoAnnotations: false,
        showFullscreenButton: false,
        mute: false,
      ),
    );

    _ytStateSubscription =
        _ytController!.videoStateStream.listen((state) {
      if (!mounted) return;

      final pos = state.position.inSeconds.toDouble();

      // Actualizar la duración real usando el getter JS directo.
      // value.metaData.duration puede llegar como Duration.zero,
      // pero _ytController!.duration llama a player.getDuration() en JS
      // y siempre devuelve el valor correcto.
      _ytController!.duration.then((durationSecs) {
        if (!mounted) return;
        if (durationSecs > 0) {
          final newDuration = Duration(seconds: durationSecs.toInt());
          if (newDuration != _totalDuration) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _totalDuration = newDuration);
            });
          }
        }
      });

      if (_isSeeking && _seekTarget != null) {
        // Liberar el bloqueo cuando el player confirma estar cerca del target
        final diff = (pos - _seekTarget!).abs();
        if (diff < 3.0 || pos > _seekTarget!) {
          _isSeeking = false;
          _seekTarget = null;
          _seekFailsafeTimer?.cancel();
          _progressNotifier.value = pos;
        }
        // Si aun no ha llegado, mantener el slider en el target
        return;
      }

      if (_isSeeking) return; // arrastrando sin haber soltado aún
      _progressNotifier.value = pos;
    });

    _ytValueSubscription = _ytController!.stream.listen((value) {
      if (!mounted) return;
      // Diferir TODOS los setState al post-frame para evitar
      // "setState() called during build" en cualquier edge case
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (!_ytPlayerReady && value.playerState != PlayerState.unknown) {
          setState(() => _ytPlayerReady = true);
          debugPrint('YouTubePlayer: listo para recibir comandos');
        }

        final durationSecs = value.metaData.duration.inSeconds.toDouble();
        if (durationSecs > 0 &&
            durationSecs != _totalDuration.inSeconds.toDouble()) {
          setState(() {
            _totalDuration = Duration(seconds: durationSecs.toInt());
          });
        }

        final isPlaying = value.playerState == PlayerState.playing;
        if (isPlaying != _isPlaying) {
          setState(() => _isPlaying = isPlaying);
        }

        if (value.playerState == PlayerState.ended) {
          _skipSong(autoPlayNext: true);
        }
      });
    });
  }

  Future<void> _ytLoadAndPlay(String title, String artist) async {
    setState(() => _ytSearching = true);
    final videoId = await _youtubeService.searchVideo(title, artist);
    if (!mounted) return;
    setState(() { _currentYtVideoId = videoId; _ytSearching = false; });
    if (videoId == null || videoId.isEmpty) {
      _showError('No se encontró "$title" en YouTube');
      return;
    }

    // Esperar a que el player esté listo (máx 5 segundos)
    int retries = 0;
    while (!_ytPlayerReady && retries < 25) {
      await Future.delayed(const Duration(milliseconds: 200));
      retries++;
    }
    if (!mounted) return;

    debugPrint('YouTubePlayer: cargando video $videoId (ready=$_ytPlayerReady)');
    _ytController?.loadVideoById(videoId: videoId);

    // Play explícito tras un breve delay (el autoplay del navegador puede estar bloqueado)
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) _ytController?.playVideo();
  }

  void _ytPlay() => _ytController?.playVideo();
  void _ytPause() => _ytController?.pauseVideo();

  // ─────────────────────────────────────────────────────────────
  // MODO 2: Spotify Premium
  // ─────────────────────────────────────────────────────────────

  void _initSpotifyPremium() {
    if (!_spotifyPremium.isAuthenticated) {
      // Mostrar prompt de login al usuario
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSpotifyLoginDialog();
      });
    } else {
      _startSpotifyPolling();
    }
  }

  void _startSpotifyPolling() {
    _spotifyPollingTimer?.cancel();
    _spotifyPollingTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      final state = await _spotifyPremium.getPlaybackState();
      if (state == null || !mounted) return;

      final isPlaying = state['is_playing'] as bool? ?? false;
      final progressMs = state['progress_ms'] as int? ?? 0;
      final durationMs =
          (state['item']?['duration_ms'] as int?) ?? 180000;

      if (isPlaying != _isPlaying) {
        setState(() => _isPlaying = isPlaying);
      }
      if (!_isSeeking) _progressNotifier.value = progressMs / 1000.0;
      // Para Spotify: liberar el flag si la posición confirmó el seek
      if (_isSeeking && _seekTarget != null) {
        final diff = ((progressMs / 1000.0) - _seekTarget!).abs();
        if (diff < 5.0) {
          _isSeeking = false;
          _seekTarget = null;
          _seekFailsafeTimer?.cancel();
        }
      }
      final newDuration = Duration(milliseconds: durationMs);
      if (newDuration != _totalDuration) {
        setState(() => _totalDuration = newDuration);
      }
    });
  }

  Future<void> _spotifyPremiumPlay(String title, String artist) async {
    final trackId = await _spotifyPremium.searchTrackId(title, artist);
    if (trackId == null) {
      _showError('No se encontró "$title" en Spotify');
      return;
    }
    await _spotifyPremium.playTrack(trackId);
    if (mounted) setState(() => _isPlaying = true);
  }


  void _showSpotifyLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F11),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Conectar Spotify Premium',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: Color(0xFF1DB954), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Para el control total necesitas autenticarte con tu cuenta Spotify Premium.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _spotifyAuthInProgress = true);
              await _spotifyPremium.authenticate();
              if (mounted) {
                setState(() => _spotifyAuthInProgress = false);
                _startSpotifyPolling();
              }
            },
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Conectar con Spotify'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODO 1: Spotify Free
  // ─────────────────────────────────────────────────────────────

  Future<void> _spotifyFreeOpen(String title, String artist) async {
    final success = await _spotifyFree.searchAndOpen(title, artist);
    if (!success && mounted) {
      _showError('No se encontró "$title" en Spotify.\nIntenta buscarlo manualmente.');
    } else if (mounted) {
      setState(() => _isPlaying = true);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CONTROL UNIFICADO DE REPRODUCCIÓN
  // ─────────────────────────────────────────────────────────────

  /// Llamado cuando cambia la canción en cola. Actúa según el modo activo.
  Future<void> _onNewSong(String title, String artist) async {
    // Resetear progreso y duración al cambiar de canción.
    // Esto es seguro aquí porque _onNewSong siempre se llama
    // via Future.microtask() desde el StreamBuilder.
    _progressNotifier.value = 0.0;
    setState(() => _totalDuration = Duration.zero);

    switch (_mode) {
      case RoomMode.spotifyFree:
        setState(() => _isPlaying = false);
        break;
      case RoomMode.spotifyPremium:
        await _spotifyPremiumPlay(title, artist);
        break;
      case RoomMode.youtubeIntegrated:
        await _ytLoadAndPlay(title, artist);
        break;
    }
  }

  void _onPlayPause() {
    switch (_mode) {
      case RoomMode.spotifyFree:
        // En free no podemos controlar Spotify — mostramos indicación
        _showInfo('Controla la reproducción directamente en Spotify');
        break;
      case RoomMode.spotifyPremium:
        if (_isPlaying) {
          _spotifyPremium.pause();
          setState(() => _isPlaying = false);
        } else {
          _spotifyPremium.resume();
          setState(() => _isPlaying = true);
        }
        break;
      case RoomMode.youtubeIntegrated:
        if (_isPlaying) {
          _ytPause();
        } else {
          _ytPlay();
        }
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // GESTIÓN DE COLA (FIRESTORE)
  // ─────────────────────────────────────────────────────────────

  Future<void> _skipSong({bool autoPlayNext = false}) async {
    if (_currentPlayingDocId == null) return;
    final docToDelete = _currentPlayingDocId;
    _progressNotifier.value = 0.0;
    _currentYtVideoId = null;

    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(_pin)
        .collection('playlist')
        .doc(docToDelete)
        .delete();

    if (!autoPlayNext && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Canción saltada',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF39FF14),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          margin: const EdgeInsets.all(20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS UI
  // ─────────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      backgroundColor: const Color(0xFF39FF14),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }


  String _formatTime(double seconds, {bool isTotal = false}) {
    final s = isTotal ? _totalDuration.inSeconds : seconds.round();
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec < 10 ? '0$sec' : '$sec'}';
  }

  Color get _modeAccentColor {
    switch (_mode) {
      case RoomMode.spotifyFree:
      case RoomMode.spotifyPremium:
        return const Color(0xFF1DB954);
      case RoomMode.youtubeIntegrated:
        return const Color(0xFFFF0000);
    }
  }

  String get _modeBadgeLabel {
    switch (_mode) {
      case RoomMode.spotifyFree:
        return 'SPOTIFY FREE';
      case RoomMode.spotifyPremium:
        return 'SPOTIFY PREMIUM';
      case RoomMode.youtubeIntegrated:
        return 'YOUTUBE';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_pin.isEmpty) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFF39FF14))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Panel DJ'),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _modeAccentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _modeAccentColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                _modeBadgeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _modeAccentColor,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_mode == RoomMode.spotifyPremium)
            IconButton(
              icon: Icon(
                _spotifyPremium.isAuthenticated
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
                color: _spotifyPremium.isAuthenticated
                    ? const Color(0xFF1DB954)
                    : Colors.grey,
              ),
              tooltip: _spotifyPremium.isAuthenticated
                  ? 'Spotify conectado'
                  : 'Conectar Spotify',
              onPressed: () {
                if (!_spotifyPremium.isAuthenticated) {
                  _showSpotifyLoginDialog();
                }
              },
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F0F11), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: _pin.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF39FF14)))
              : StreamBuilder<QuerySnapshot>(
                  stream: _playlistStream,
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];
                    final hasSongs = docs.isNotEmpty;
                    final currentData = hasSongs
                        ? (docs.first.data() as Map<String, dynamic>)
                        : null;
                    final nextDocId = hasSongs ? docs.first.id : null;

                    // Detectar cambio de canción
                    if (nextDocId != _currentPlayingDocId) {
                      _currentPlayingDocId = nextDocId;
                      _progressNotifier.value = 0.0;

                      if (hasSongs && currentData != null) {
                        final title =
                            currentData['title'] as String? ?? '';
                        final artist =
                            currentData['artist'] as String? ?? '';
                        if (title.isNotEmpty) {
                          Future.microtask(
                              () => _onNewSong(title, artist));
                        }
                      } else {
                        // Cola vacía: diferir el setState para no crashear
                        // si el stream de Firestore llega durante el build
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_mode == RoomMode.youtubeIntegrated) {
                            _ytController?.pauseVideo();
                            setState(() {
                              _currentYtVideoId = null;
                              _isPlaying = false;
                            });
                          } else if (_mode == RoomMode.spotifyPremium) {
                            _spotifyPremium.pause();
                            setState(() => _isPlaying = false);
                          } else {
                            setState(() => _isPlaying = false);
                          }
                        });
                      }
                    }

                    final title = currentData?['title'] as String? ??
                        'Esperando canciones del público...';
                    final artist = currentData?['artist'] as String? ??
                        'Los invitados pueden añadir temas usando el PIN';
                    final thumbnail =
                        currentData?['thumbnailUrl'] as String? ?? '';

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // Card más pequeño — la info está debajo, no dentro

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Código de sala ──────────────────────────
                              _buildRoomCodeCard(),
                              const SizedBox(height: 8),

                              // ── Banner modo Spotify Free ─────────────────
                              if (_mode == RoomMode.spotifyFree && hasSongs)
                                _buildSpotifyFreeBanner(
                                    currentData?['title'] as String? ?? '',
                                    currentData?['artist'] as String? ?? ''),

                              // ── Reproductor visual (solo imagen/video) ────
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: _buildPlayerCard(hasSongs, thumbnail),
                              ),

                              // ── Info canción (fuera del Stack/iframe) ─────
                              _buildSongInfo(hasSongs, title, artist),

                              // ── Barra de progreso (fuera del iframe!) ─────
                              if (_mode != RoomMode.spotifyFree)
                                _buildProgressBarWidget(hasSongs),

                              const SizedBox(height: 4),

                              // ── Controles ───────────────────────────────
                              _buildControls(hasSongs),
                              const SizedBox(height: 8),

                              // ── Cola ────────────────────────────────────
                              _buildQueueSection(snapshot, docs, hasSongs),
                            ],
                          ),
                        );
                      },
                    );

                  },
                ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────────────────────

  Widget _buildRoomCodeCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CÓDIGO DE SALA',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(_pin,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFC42261))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpotifyFreeBanner(String title, String artist) {
    return GestureDetector(
      onTap: () => _spotifyFreeOpen(title, artist),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1DB954).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF1DB954).withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.play_circle_filled_rounded,
                  color: Color(0xFF1DB954), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isNotEmpty ? title : 'Canción en cola',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1DB954),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '▶  Toca aquí → Spotify se abre/actualiza → Da play',
                    style: TextStyle(
                      color: Color(0xFF1DB954),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFF1DB954), size: 16),
          ],
        ),
      ),
    );
  }


  // ── Player card: SOLO VISUAL (video/thumbnail + gradiente + ecualizador) ──
  // La info de canción y la barra de progreso están FUERA del Stack,
  // así el Slider no compite con el iframe de YouTube por los eventos.
  Widget _buildPlayerCard(bool hasSongs, String thumbnail,
      {double? height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasSongs
              ? _modeAccentColor.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.05),
        ),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // YouTube: IgnorePointer evita que el iframe capture clics
            // que deben ir al Slider (que está fuera, debajo del card)
            if (_mode == RoomMode.youtubeIntegrated && _ytController != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: YoutubePlayer(
                    controller: _ytController!,
                    aspectRatio: 16 / 9,
                  ),
                ),
              ),

            // Thumbnail para modos Spotify
            if (_mode != RoomMode.youtubeIntegrated && thumbnail.isNotEmpty)
              Positioned.fill(
                child: Image.network(thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),

            // Gradiente oscuro
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
            ),

            // Ecualizador animado
            if (hasSongs && _isPlaying)
              Positioned(
                top: 12,
                right: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    _waveHeights.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOut,
                      width: 3,
                      height: _waveHeights[i],
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: _modeAccentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Info de canción: badge + título + artista (FUERA del iframe) ──────────
  Widget _buildSongInfo(bool hasSongs, String title, String artist) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Badge modo
          if (hasSongs)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _modeAccentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _modeAccentColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                _modeBadgeLabel,
                style: TextStyle(
                    color: _modeAccentColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900),
              ),
            ),
          // Título
          Expanded(
            child: Text(
              _ytSearching && _mode == RoomMode.youtubeIntegrated
                  ? 'Buscando en YouTube...'
                  : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ),
          // Spinner búsqueda YouTube
          if (_ytSearching && _mode == RoomMode.youtubeIntegrated)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    color: Color(0xFFFF0000), strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  // ── Barra de progreso: FUERA del Stack → el Slider recibe eventos ─────────
  Widget _buildProgressBarWidget(bool hasSongs) {
    return ValueListenableBuilder<double>(
      valueListenable: _progressNotifier,
      builder: (ctx, progress, _) {
        final maxVal = _totalDuration.inSeconds.toDouble() > 0
            ? _totalDuration.inSeconds.toDouble()
            : 600.0; // fallback de 10 min mientras YouTube reporta la duración
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(ctx).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: _modeAccentColor,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: _modeAccentColor,
                overlayColor: _modeAccentColor.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: hasSongs ? progress.clamp(0.0, maxVal) : 0.0,
                max: maxVal,
                onChanged: hasSongs
                    ? (val) {
                        // Congelar actualizaciones del stream mientras se arrastra
                        _isSeeking = true;
                        _progressNotifier.value = val;
                      }
                    : null,
                onChangeEnd: hasSongs
                    ? (val) {
                        // Clampear al máximo real para no buscar más allá del final
                        final maxSecs = _totalDuration.inSeconds.toDouble();
                        final clampedVal = maxSecs > 0
                            ? val.clamp(0.0, maxSecs - 2.0)
                            : val;

                        // Marcar estado de seek y guardar target
                        _isSeeking = true;
                        _seekTarget = clampedVal;
                        _progressNotifier.value = clampedVal;

                        // Failsafe: liberar si el stream no confirma en 8s
                        _seekFailsafeTimer?.cancel();
                        _seekFailsafeTimer = Timer(
                          const Duration(seconds: 8),
                          () {
                            if (mounted) {
                              _isSeeking = false;
                              _seekTarget = null;
                            }
                          },
                        );

                        switch (_mode) {
                          case RoomMode.youtubeIntegrated:
                            // loadVideoById con startSeconds es MÁS FIABLE que seekTo:
                            // seekTo usa eval() que YouTube ignora si está buffering.
                            // loadVideoById usa el canal run() con JSON y siempre funciona.
                            if (_currentYtVideoId != null &&
                                _currentYtVideoId!.isNotEmpty) {
                              _ytController?.loadVideoById(
                                videoId: _currentYtVideoId!,
                                startSeconds: clampedVal,
                              );
                            } else {
                              // Fallback: intentar seekTo igualmente
                              _ytController?.seekTo(
                                  seconds: clampedVal, allowSeekAhead: true);
                            }
                          case RoomMode.spotifyPremium:
                            _spotifyPremium
                                .seek(Duration(seconds: clampedVal.toInt()));
                          case RoomMode.spotifyFree:
                            _isSeeking = false;
                            _seekTarget = null;
                        }
                      }
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatTime(hasSongs ? progress : 0.0),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                  Text(
                    _formatTime(
                        _totalDuration.inSeconds.toDouble(),
                        isTotal: true),
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(bool hasSongs) {
    final bool canPlayPause =
        hasSongs && _mode != RoomMode.spotifyFree;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Skip Previous (siempre desactivado — no tenemos historial)
        IconButton(
          onPressed: null,
          icon: const Icon(Icons.skip_previous_rounded, size: 36),
          disabledColor: Colors.white.withValues(alpha: 0.1),
        ),
        const SizedBox(width: 24),

        // Play / Pause
        FloatingActionButton.large(
          onPressed: canPlayPause ? _onPlayPause : null,
          backgroundColor: canPlayPause
              ? _modeAccentColor
              : Colors.white.withValues(alpha: 0.08),
          foregroundColor:
              canPlayPause ? Colors.black : Colors.white.withValues(alpha: 0.2),
          elevation: canPlayPause ? 8 : 0,
          child: _spotifyAuthInProgress
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Icon(
                  _isPlaying && hasSongs
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 40,
                ),
        ),
        const SizedBox(width: 24),

        // Skip Next
        IconButton(
          onPressed: hasSongs ? () => _skipSong() : null,
          icon: const Icon(Icons.skip_next_rounded, size: 36),
          color: Colors.white,
          disabledColor: Colors.white.withValues(alpha: 0.1),
        ),
      ],
    );
  }

  Widget _buildQueueSection(AsyncSnapshot<QuerySnapshot> snapshot,
      List<QueryDocumentSnapshot> docs, bool hasSongs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SIGUIENTE EN LA COLA',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.grey)),
              // Botón para que el DJ añada canciones él mismo
              TextButton.icon(
                onPressed: _showAddSongBottomSheet,
                icon: Icon(Icons.add_rounded, size: 16, color: _modeAccentColor),
                label: Text(
                  'AÑADIR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _modeAccentColor,
                    letterSpacing: 0.8,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: _modeAccentColor.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: snapshot.connectionState == ConnectionState.waiting
                ? const SizedBox.shrink()
                : !hasSongs
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Esperando canciones del público...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.4))),
                            const SizedBox(height: 4),
                            Text('Comparte el PIN $_pin con tus amigos',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.25))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: docs.length - 1 < 0 ? 0 : docs.length - 1,
                        itemBuilder: (context, i) {
                          final doc = docs[i + 1];
                          final song =
                              doc.data() as Map<String, dynamic>;
                          final thumb =
                              song['thumbnailUrl'] as String? ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.01),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.04)),
                            ),
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: thumb.isNotEmpty
                                    ? Image.network(thumb,
                                        width: 55,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (_, __, ___) => _thumbPlaceholder())
                                    : _thumbPlaceholder(),
                              ),
                              title: Text(
                                  song['title'] as String? ?? 'Sin Título',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  song['artist'] as String? ??
                                      'Artista Desconocido',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.reorder_rounded,
                                  color: Colors.grey, size: 20),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 55,
      height: 40,
      color: Colors.white.withValues(alpha: 0.05),
      child: const Icon(Icons.music_note_rounded, color: Colors.grey),
    );
  }
}
