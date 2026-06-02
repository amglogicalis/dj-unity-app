import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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

/// Pantalla del Guest (Invitado) con búsqueda dinámica inteligente conectada a Firestore.
class GuestRoomPage extends StatefulWidget {
  const GuestRoomPage({super.key});

  @override
  State<GuestRoomPage> createState() => _GuestRoomPageState();
}

class _GuestRoomPageState extends State<GuestRoomPage> {
  final TextEditingController _searchController = TextEditingController();
  List<GuestSongMock> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Desencadena la búsqueda con un retardo para evitar sobrecargar de peticiones
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _performSearch(query);
    });
  }

  /// Realiza la consulta HTTP real hacia el catálogo de iTunes (CORS-friendly)
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
      final response = await http.get(
        Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(cleanQuery)}&media=music&limit=15'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        final List<GuestSongMock> tempResults = [];

        for (var item in results) {
          if (item is Map<String, dynamic>) {
            final trackName = item['trackName'] as String? ?? 'Canción sin título';
            final artistName = item['artistName'] as String? ?? 'Artista desconocido';
            final artworkUrl = item['artworkUrl100'] as String? ?? '';
            final trackId = item['trackId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

            tempResults.add(
              GuestSongMock(
                title: trackName,
                artist: artistName,
                platform: 'itunes',
                videoId: trackId,
                thumbnailUrl: artworkUrl,
              ),
            );
          }
        }

        setState(() {
          _searchResults = tempResults;
          _isLoading = false;
        });
      } else {
        throw Exception('Servidor de iTunes respondió con código ${response.statusCode}');
      }
    } catch (e) {
      // Fallback local en caso de error de red
      final List<GuestSongMock> fallbackResults = [];
      final capitalizedQuery = cleanQuery.split(' ').map((w) {
        if (w.isEmpty) return '';
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

      final List<String> suffixes = const [
        ' (Official Video)',
        ' (Live Performance)',
        ' (Lyrics Video)',
        ' (Official Audio)',
      ];

      for (int i = 0; i < 4; i++) {
        fallbackResults.add(
          GuestSongMock(
            title: '$capitalizedQuery${suffixes[i]}',
            artist: 'Apple Music Fallback',
            platform: 'itunes',
            videoId: 'fallback_${i}_${DateTime.now().millisecondsSinceEpoch}',
            thumbnailUrl: '',
          ),
        );
      }

      setState(() {
        _searchResults = fallbackResults;
        _isLoading = false;
      });

      debugPrint('Error de búsqueda en iTunes: $e. Activando resultados locales.');
    }
  }

  /// Agrega la canción seleccionada a Cloud Firestore en tiempo real de forma instantánea
  Future<void> _addSongToQueue(GuestSongMock song) async {
    final roomPin = ModalRoute.of(context)?.settings.arguments as String? ?? '0000';

    setState(() {
      _isLoading = true;
    });

    try {
      // Guardar el documento en Firestore inmediatamente (sin esperas de scrap de YouTube/Invidious)
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(roomPin)
          .collection('playlist')
          .add({
        'title': song.title,
        'artist': song.artist,
        'platform': 'spotify',
        'videoOrTrackId': song.videoId, // Usamos la ID original de iTunes
        'thumbnailUrl': song.thumbnailUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Feedback visual premium
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡"${song.title}" agregada a la cola de la sala $roomPin!',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: const Color(0xFF39FF14),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al agregar canción: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    // Limpiar buscador tras añadir
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pin = ModalRoute.of(context)?.settings.arguments as String? ?? '0000';

    return Scaffold(
      appBar: AppBar(
        title: Text('Sala: $pin'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F0F11),
              Color(0xFF000000),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Buscar y Añadir',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC42261).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Invitado',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFC42261),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Caja de búsqueda interactiva
                TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: _performSearch,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Buscar canciones (ej: Coldplay, Karol G)...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.02),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFC42261), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Resultados de búsqueda dinámicos o indicador de carga
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFC42261),
                          ),
                        )
                      : _searchResults.isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'RESULTADOS ENCONTRADOS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final song = _searchResults[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.01),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withOpacity(0.04)),
                                    ),
                                    child: ListTile(
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          song.thumbnailUrl,
                                          width: 55,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              width: 55,
                                              height: 40,
                                              color: Colors.redAccent.withOpacity(0.1),
                                              child: const Icon(Icons.play_arrow_rounded, color: Colors.redAccent),
                                            );
                                          },
                                        ),
                                      ),
                                      title: Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFC42261)),
                                        onPressed: () => _addSongToQueue(song),
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
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                size: 64,
                                color: Colors.white.withOpacity(0.1),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Explora el catálogo mundial',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Escribe "Coldplay", "Bad Bunny", "Rosalia" o tu canción favorita',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
