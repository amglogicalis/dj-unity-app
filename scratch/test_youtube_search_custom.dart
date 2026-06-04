import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;

// Copiamos la lógica exacta de YouTubeService
class YouTubeServiceLocal {
  static const _timeout = Duration(seconds: 8);
  static const _maxCandidates = 3;

  static const _pipedInstances = [
    'https://pipedapi.in.projectsegfau.lt',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.kavin.rocks',
  ];

  static const _invidiousInstances = [
    'https://iv.ggtyler.dev',
    'https://invidious.slipfox.xyz',
    'https://invidious.privacyredirect.com',
  ];

  Future<String?> searchVideo(String title, String artist) async {
    final cleanTitle = _cleanTitle(title);
    final queries = [
      if (artist.isNotEmpty) '$artist $cleanTitle',
      if (artist.isNotEmpty) '$artist $title',
      '$cleanTitle',
      '$cleanTitle - Topic',
      '$cleanTitle official audio',
    ];

    for (final query in queries) {
      print('  Trying query: "$query"');
      // 1. YouTube Scraping
      final idScrape = await _searchYoutubeScrape(query);
      if (idScrape != null) {
        print('    ✓ Scrape match: $idScrape');
        return idScrape;
      }

      // 2. Piped
      final idPiped = await _searchPiped(query);
      if (idPiped != null) {
        print('    ✓ Piped match: $idPiped');
        return idPiped;
      }

      // 3. Invidious
      final idInvidious = await _searchInvidious(query);
      if (idInvidious != null) {
        print('    ✓ Invidious match: $idInvidious');
        return idInvidious;
      }
    }
    return null;
  }

  Future<bool> _isEmbeddable(String videoId) async {
    const oembedBase = 'https://www.youtube.com/oembed';
    final videoUrl = 'https://www.youtube.com/watch?v=$videoId';
    final checkUrl = '$oembedBase?url=${Uri.encodeComponent(videoUrl)}&format=json';
    try {
      final resp = await http.get(Uri.parse(checkUrl)).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) return true;
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        print('      ↷ $videoId: embed blocked (${resp.statusCode})');
        return false;
      }
    } catch (_) {}
    return true;
  }

  Future<String?> _searchYoutubeScrape(String query) async {
    final ytSearchUrl = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';
    final candidates = await _fetchScrapeCandidates(ytSearchUrl);
    for (final id in candidates) {
      if (await _isEmbeddable(id)) return id;
    }
    return null;
  }

  Future<List<String>> _fetchScrapeCandidates(String url) async {
    final ids = <String>[];
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/91 Mobile Safari/537.36',
      }).timeout(_timeout);
      if (resp.statusCode != 200) return ids;
      final body = resp.body;
      final seen = <String>{};
      for (final pattern in [
        RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"'),
        RegExp(r'watch\?v=([a-zA-Z0-9_-]{11})'),
      ]) {
        for (final match in pattern.allMatches(body)) {
          if (ids.length >= _maxCandidates) break;
          final id = match.group(1)!;
          if (id != 'undefined' && id.length == 11 && seen.add(id)) ids.add(id);
        }
        if (ids.length >= _maxCandidates) break;
      }
    } catch (e) {
      print('      Scrape error: $e');
    }
    return ids;
  }

  Future<String?> _searchPiped(String query) async {
    for (final filter in ['music_songs', 'videos']) {
      for (final base in _pipedInstances) {
        final pipedUrl = '$base/search?q=${Uri.encodeComponent(query)}&filter=$filter';
        final candidates = await _fetchPipedCandidates(pipedUrl);
        for (final id in candidates) {
          if (await _isEmbeddable(id)) return id;
        }
      }
    }
    return null;
  }

  Future<List<String>> _fetchPipedCandidates(String url) async {
    final ids = <String>[];
    try {
      final resp = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(_timeout);
      if (resp.statusCode != 200) return ids;
      final data = jsonDecode(resp.body);
      if (data is! Map) return ids;
      final items = data['items'] as List? ?? [];
      for (final item in items) {
        if (ids.length >= _maxCandidates) break;
        if (item is! Map) continue;
        final watchUrl = item['url'] as String? ?? '';
        final match = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl) ??
            RegExp(r'/watch\?v=([a-zA-Z0-9_-]{11})').firstMatch(watchUrl);
        if (match != null) { ids.add(match.group(1)!); continue; }
        final vid = item['videoId'] as String?;
        if (vid != null && vid.length == 11) ids.add(vid);
      }
    } catch (e) {
      print('      Piped error: $e');
    }
    return ids;
  }

  Future<String?> _searchInvidious(String query) async {
    for (final base in _invidiousInstances) {
      final invUrl = '$base/api/v1/search?q=${Uri.encodeComponent(query)}&type=video&fields=videoId';
      try {
        final resp = await http.get(Uri.parse(invUrl), headers: {'Accept': 'application/json'}).timeout(_timeout);
        if (resp.statusCode != 200) continue;
        final data = jsonDecode(resp.body);
        if (data is! List || data.isEmpty) continue;
        final first = data.first;
        if (first is! Map) continue;
        final vid = first['videoId'] as String?;
        if (vid != null && vid.length == 11 && await _isEmbeddable(vid)) return vid;
      } catch (e) {
        // print('      Invidious error ($base): $e');
      }
    }
    return null;
  }

  String _cleanTitle(String title) => title
      .replaceAll(RegExp(r'\s*\(feat\..*?\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\[feat\..*?\]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*ft\..*?(?=\s|$)', caseSensitive: false), '')
      .trim();
}

void main() async {
  final service = YouTubeServiceLocal();
  final searchTitle = 'Luz apaga';
  
  // Vamos a probar con artista vacío y con Ozuna
  for (final artist in ['', 'Ozuna']) {
    print('\n======================================');
    print('Testing Search for: "$searchTitle" by "$artist"');
    print('======================================');
    
    final videoId = await service.searchVideo(searchTitle, artist);
    if (videoId == null) {
      print('❌ FAILED to find any videoId for "$searchTitle" by "$artist"');
      continue;
    }
    
    print('✓ Found Video ID: $videoId');
    
    // Ahora probamos la extracción del stream candidato
    final yteClient = yte.YoutubeExplode();
    try {
      print('Attempting to fetch manifest for $videoId...');
      final manifest = await yteClient.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          yte.YoutubeApiClient.ios,
          yte.YoutubeApiClient.mweb,
          yte.YoutubeApiClient.tv,
        ],
      ).timeout(const Duration(seconds: 12));
      
      final audioStreams = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      print('Found ${audioStreams.length} audio streams.');
      
      if (audioStreams.isEmpty) {
        print('❌ No audio streams available in manifest.');
        continue;
      }
      
      int successCount = 0;
      for (final stream in audioStreams) {
        final candidate = stream.url.toString();
        print('  Testing stream: ${stream.audioCodec} (${stream.bitrate})');
        
        try {
          final resp = await http.head(Uri.parse(candidate)).timeout(const Duration(seconds: 4));
          print('    HEAD status: ${resp.statusCode}');
          if (resp.statusCode != 403) {
            successCount++;
            print('    ✓ Stream is accessible!');
          } else {
            print('    ❌ Stream returned 403 Forbidden!');
          }
        } catch (e) {
          print('    ⚠️ HEAD request failed: $e');
        }
      }
      print('Streams accessible: $successCount out of ${audioStreams.length}');
      
    } catch (e) {
      print('❌ Failed to fetch manifest or error occurred: $e');
    } finally {
      yteClient.close();
    }
  }
}
