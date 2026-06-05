import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// Modelo local que representa una canción buscada en la vista de Invitado
class GuestSongMock {
  final String title;
  final String artist;
  final String platform;
  final String videoId;
  final String thumbnailUrl;

  const GuestSongMock({
    required this.title,
    required this.artist,
    required this.platform,
    required this.videoId,
    required this.thumbnailUrl,
  });
}

/// Pantalla del Guest (Invitado):
/// - Muestra la canción que está sonando ahora (Firestore stream, 1er doc)
/// - Muestra la cola de canciones siguientes
/// - Permite añadir canciones vía FAB → bottom sheet de búsqueda
class GuestRoomPage extends StatefulWidget {
  const GuestRoomPage({super.key});

  @override
  State<GuestRoomPage> createState() => _GuestRoomPageState();
}

class _GuestRoomPageState extends State<GuestRoomPage> {
  // ── Búsqueda ──────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  List<GuestSongMock> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;

  // ── Firestore: cola de la sala ─────────────────────────────────
  Stream<QuerySnapshot>? _playlistStream;
  String? _roomPin;
  StreamSubscription<DocumentSnapshot>? _roomSubscription;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _roomSubscription?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // BÚSQUEDA (lógica sin cambios)
  // ─────────────────────────────────────────────────────────────

  Future<http.Response> _performGetWithCorsProxy(
    String targetUrl, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!kIsWeb) {
      return http.get(Uri.parse(targetUrl), headers: headers).timeout(timeout);
    }

    final proxyCandidates = [
      'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(targetUrl)}',
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(targetUrl)}',
      'https://corsproxy.io/?url=${Uri.encodeComponent(targetUrl)}',
    ];

    dynamic lastException;
    for (final proxyUrl in proxyCandidates) {
      try {
        debugPrint('Invitado proxy: intentando GET vía $proxyUrl');
        final response = await http.get(Uri.parse(proxyUrl)).timeout(timeout);
        if (response.statusCode == 200) {
          return response;
        }
        debugPrint('Invitado proxy ($proxyUrl) falló con status: ${response.statusCode}');
      } catch (e) {
        debugPrint('Invitado proxy error ($proxyUrl): $e');
        lastException = e;
      }
    }
    throw lastException ?? Exception('Todos los proxies CORS fallaron para $targetUrl');
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _performSearch(query);
    });
  }

  /// Realiza la consulta HTTP real hacia el catálogo:
  /// - iOS (defaultTargetPlatform == iOS): iTunes API (catálogo de Apple Music)
  /// - Android / Windows / Web no-iOS: MusicBrainz (catálogo completo de 100M+ canciones)
  Future<void> _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

      if (isIOS) {
        await _searchWithItunes(cleanQuery);
      } else {
        await _searchWithMusicBrainz(cleanQuery);
      }
    } catch (e) {
      debugPrint('Error en búsqueda: $e');
      try {
        await _searchWithMusicBrainz(cleanQuery);
      } catch (e2) {
        debugPrint('MusicBrainz también falló: $e2');
        setState(() {
          _isLoading = false;
          _searchResults = [];
        });
      }
    }
  }

  Future<void> _searchWithMusicBrainz(String query) async {
    debugPrint('Búsqueda MusicBrainz: "$query"');
    final encodedQuery = Uri.encodeComponent(query);
    final mbUrl =
        'https://musicbrainz.org/ws/2/recording?query=$encodedQuery&fmt=json&limit=25';

    final response = await _performGetWithCorsProxy(
      mbUrl,
      headers: {
        'User-Agent': 'DemocraticDJ/1.0 (https://democratic-dj-fe97d.web.app)',
        'Accept': 'application/json',
      },
      timeout: const Duration(seconds: 12),
    );

    if (response.statusCode != 200) {
      throw Exception('MusicBrainz devolvió status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final recordings = data['recordings'] as List<dynamic>? ?? [];
    final List<GuestSongMock> results = [];
    final seen = <String>{};

    for (final recording in recordings) {
      if (recording is! Map<String, dynamic>) continue;
      final title = recording['title'] as String? ?? 'Canción sin título';
      final mbid = recording['id'] as String? ?? '';
      final score = recording['score'] as int? ?? 0;
      if (score < 30) continue;

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

      results.add(GuestSongMock(
        title: title,
        artist: artistName,
        platform: 'musicbrainz',
        videoId: mbid,
        thumbnailUrl: thumbnailUrl,
      ));
    }

    debugPrint('MusicBrainz: encontradas ${results.length} canciones únicas');
    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
  }

  Future<void> _searchWithItunes(String query) async {
    debugPrint('Búsqueda iTunes (iOS): "$query"');
    final targetUrl =
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&entity=song&limit=25&country=us';
    
    final response = await _performGetWithCorsProxy(
      targetUrl,
      timeout: const Duration(seconds: 10),
    );
    
    if (response.statusCode == 200) {
      _parseItunesResponse(response.body);
      return;
    }
    throw Exception('iTunes devolvió status ${response.statusCode}');
  }

  void _parseItunesResponse(String responseBody) {
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];
    final List<GuestSongMock> tempResults = [];
    final seen = <String>{};

    for (var item in results) {
      if (item is Map<String, dynamic>) {
        final wrapperType = item['wrapperType'] as String? ?? '';
        if (wrapperType.isNotEmpty && wrapperType != 'track') continue;

        final trackName = item['trackName'] as String? ?? 'Canción sin título';
        final artistName =
            item['artistName'] as String? ?? 'Artista desconocido';
        final artworkUrl = (item['artworkUrl100'] as String? ?? '')
            .replaceAll('100x100', '250x250');
        final trackId = item['trackId']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString();

        final key =
            '${trackName.toLowerCase()}|${artistName.toLowerCase()}';
        if (seen.contains(key)) continue;
        seen.add(key);

        tempResults.add(GuestSongMock(
          title: trackName,
          artist: artistName,
          platform: 'itunes',
          videoId: trackId,
          thumbnailUrl: artworkUrl,
        ));
      }
    }

    setState(() {
      _searchResults = tempResults;
      _isLoading = false;
    });
  }

  /// Agrega la canción seleccionada a Cloud Firestore
  Future<void> _addSongToQueue(GuestSongMock song) async {
    final pin = _roomPin ?? '0000';

    try {
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(pin)
          .collection('playlist')
          .add({
        'title': song.title,
        'artist': song.artist,
        'platform': 'spotify',
        'videoOrTrackId': song.videoId,
        'thumbnailUrl': song.thumbnailUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡"${song.title}" agregada a la cola!',
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF39FF14),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al agregar canción: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BOTTOM SHEET DE BÚSQUEDA
  // ─────────────────────────────────────────────────────────────

  void _showSearchBottomSheet() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _isLoading = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void onChanged(String q) {
              _onSearchChanged(q);
              // Re-render el sheet cuando cambian los resultados
              Future.delayed(const Duration(milliseconds: 700), () {
                if (ctx.mounted) setSheetState(() {});
              });
            }

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F11),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
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
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFC42261).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.search_rounded,
                              color: Color(0xFFC42261), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Buscar y añadir',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  // Campo de búsqueda
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: onChanged,
                      onSubmitted: (q) {
                        _performSearch(q);
                        Future.delayed(const Duration(milliseconds: 700),
                            () {
                          if (ctx.mounted) setSheetState(() {});
                        });
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar canción o artista...',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3)),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: Colors.white.withValues(alpha: 0.5)),
                        suffixIcon: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFC42261),
                                      strokeWidth: 2),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: Colors.white),
                                    onPressed: () {
                                      _searchController.clear();
                                      _performSearch('');
                                      setSheetState(() {});
                                    },
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
                          borderSide: const BorderSide(
                              color: Color(0xFFC42261), width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Resultados
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFC42261)),
                          )
                        : _searchResults.isNotEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    child: Text(
                                      'RESULTADOS ENCONTRADOS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white
                                            .withValues(alpha: 0.4),
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 4),
                                      itemCount: _searchResults.length,
                                      itemBuilder: (context, index) {
                                        final song = _searchResults[index];
                                        return Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.02),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.05)),
                                          ),
                                          child: ListTile(
                                            onTap: () async {
                                              Navigator.pop(sheetCtx);
                                              await _addSongToQueue(song);
                                            },
                                            leading: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                song.thumbnailUrl,
                                                width: 55,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (_, __, ___) =>
                                                        _thumbPlaceholder(),
                                              ),
                                            ),
                                            title: Text(
                                              song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight:
                                                      FontWeight.bold),
                                            ),
                                            subtitle: Text(
                                              song.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6)),
                                            ),
                                            trailing: IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_rounded,
                                                  color: Color(0xFFC42261),
                                                  size: 28),
                                              onPressed: () async {
                                                Navigator.pop(sheetCtx);
                                                await _addSongToQueue(song);
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              )
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.queue_music_rounded,
                                        size: 52,
                                        color: Colors.white
                                            .withValues(alpha: 0.1)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Escribe para buscar',
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.4),
                                          fontSize: 15),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '"Coldplay", "Bad Bunny", "Rosalía"...',
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.25),
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                  ),
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

  // ─────────────────────────────────────────────────────────────
  // HELPERS UI
  // ─────────────────────────────────────────────────────────────

  Widget _thumbPlaceholder() {
    return Container(
      width: 55,
      height: 40,
      color: Colors.white.withValues(alpha: 0.05),
      child: const Icon(Icons.music_note_rounded,
          color: Colors.grey, size: 20),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pin = ModalRoute.of(context)?.settings.arguments as String? ?? '0000';

    // Lazy-init del stream Firestore (solo una vez)
    _roomPin ??= pin;
    _playlistStream ??= FirebaseFirestore.instance
        .collection('rooms')
        .doc(pin)
        .collection('playlist')
        .orderBy('createdAt', descending: false)
        .snapshots();

    _roomSubscription ??= FirebaseFirestore.instance
        .collection('rooms')
        .doc(pin)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        if (!context.mounted) return;
        _roomSubscription?.cancel();
        _roomSubscription = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'La sala ha sido cerrada por el DJ.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0F),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sala: $pin'),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFC42261).withValues(alpha: 0.18),
                    const Color(0xFF39FF14).withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFC42261).withValues(alpha: 0.4)),
              ),
              child: const Text(
                'INVITADO',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFFC42261),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSearchBottomSheet,
        backgroundColor: const Color(0xFFC42261),
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Añadir canción',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C0C0F), Color(0xFF060608)],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: _playlistStream,
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final hasSongs = docs.isNotEmpty;
              final currentData = hasSongs
                  ? docs.first.data() as Map<String, dynamic>
                  : null;
              final queueDocs =
                  docs.length > 1 ? docs.sublist(1) : <QueryDocumentSnapshot>[];

              return LayoutBuilder(
                builder: (context, constraints) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── SONANDO AHORA ───────────────────────────
                        KeyedSubtree(
                          key: ValueKey(currentData?['title'] ?? ''),
                          child: _buildNowPlayingSection(hasSongs, currentData),
                        ),
                        const SizedBox(height: 20),

                        // ── COLA ─────────────────────────────────────
                        // Expanded aquí (no dentro de _buildQueueSection)
                        // garantiza constraints acotados en web/iOS/Android
                        Expanded(
                          child: _buildQueueSection(
                              snapshot, queueDocs, hasSongs),
                        ),
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
  // WIDGET: SONANDO AHORA
  // ─────────────────────────────────────────────────────────────

  Widget _buildNowPlayingSection(
      bool hasSongs, Map<String, dynamic>? data) {
    final title = data?['title'] as String? ?? 'Esperando canciones...';
    final artist = data?['artist'] as String? ??
        'El DJ aún no ha puesto ninguna canción';
    final thumb = data?['thumbnailUrl'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasSongs
              ? const Color(0xFFC42261).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: hasSongs
            ? [
                BoxShadow(
                  color: const Color(0xFF39FF14).withValues(alpha: 0.04),
                  blurRadius: 20,
                  spreadRadius: 0,
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              if (hasSongs) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF39FF14),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                hasSongs ? 'SONANDO AHORA' : 'SIN CANCIÓN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                  color: hasSongs
                      ? const Color(0xFF39FF14)
                      : Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Info canción
          Row(
            children: [
              // Portada
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: thumb.isNotEmpty
                    ? Image.network(
                        thumb,
                        key: ValueKey(thumb),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _nowPlayingPlaceholder(),
                      )
                    : _nowPlayingPlaceholder(),
              ),
              const SizedBox(width: 14),
              // Título y artista
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Icono animado si hay canción
              if (hasSongs)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.graphic_eq_rounded,
                      color: Color(0xFF39FF14), size: 28),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nowPlayingPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.2), size: 28),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // WIDGET: COLA
  // ─────────────────────────────────────────────────────────────

  Widget _buildQueueSection(
    AsyncSnapshot<QuerySnapshot> snapshot,
    List<QueryDocumentSnapshot> queueDocs,
    bool hasSongs,
  ) {
    // _buildQueueSection ya NO devuelve Expanded —
    // el Expanded está en el call site para garantizar
    // constraints acotados en web y evitar layout issues.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'A CONTINUACIÓN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              if (queueDocs.isNotEmpty)
                Text(
                  '${queueDocs.length} ${queueDocs.length == 1 ? 'canción' : 'canciones'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: snapshot.connectionState == ConnectionState.waiting
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFFC42261), strokeWidth: 2))
                : queueDocs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.queue_music_rounded,
                                size: 48,
                                color: Colors.white.withValues(alpha: 0.08)),
                            const SizedBox(height: 10),
                            Text(
                              hasSongs
                                  ? 'No hay más canciones en la cola'
                                  : 'La cola está vacía',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Toca "Añadir canción" para poner la tuya',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.2)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: queueDocs.length,
                        itemBuilder: (context, i) {
                          final song = queueDocs[i].data()
                              as Map<String, dynamic>;
                          final thumb =
                              song['thumbnailUrl'] as String? ?? '';
                          final position = i + 1;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.015),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.04)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Número de posición
                                  SizedBox(
                                    width: 22,
                                    child: Text(
                                      '$position',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white
                                            .withValues(alpha: 0.25),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Portada
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: thumb.isNotEmpty
                                        ? Image.network(
                                            thumb,
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _thumbPlaceholder(),
                                          )
                                        : _thumbPlaceholder(),
                                  ),
                                ],
                              ),
                              title: Text(
                                song['title'] as String? ?? 'Sin título',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                              subtitle: Text(
                                song['artist'] as String? ??
                                    'Artista desconocido',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.45),
                                    fontSize: 12),
                              ),
                              trailing: Icon(Icons.more_horiz_rounded,
                                  color:
                                      Colors.white.withValues(alpha: 0.2),
                                  size: 20),
                            ),
                          );
                        },
                      ),
          ),
        ],
      );
  }
}
