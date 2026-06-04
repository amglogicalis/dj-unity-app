import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final videoId = 'TWsq3QPv_Oc'; // Ozuna - Luz Apaga (el bloqueado)
  print('Testing fallback streams for blocked video ID: $videoId\n');

  final invidiousInstances = [
    'invidious.io.lol',
    'yewtu.be',
    'invidious.flokinet.to',
    'inv.tux.im',
    'iv.ggtyler.dev',
    'invidious.privacyredirect.com',
  ];

  print('--- Testing Invidious latest_version &local=true ---');
  for (final instance in invidiousInstances) {
    final url = 'https://$instance/latest_version?id=$videoId&itag=140&local=true';
    print('Testing: $url');
    try {
      final resp = await http.head(Uri.parse(url)).timeout(Duration(seconds: 5));
      print('  HEAD status: ${resp.statusCode}');
      if (resp.statusCode >= 200 && resp.statusCode < 400 || resp.statusCode == 405) {
        print('  ✓ SUCCESS (HEAD status: ${resp.statusCode})');
        // Probamos un GET parcial para asegurar
        final getResp = await http.get(Uri.parse(url), headers: {'Range': 'bytes=0-10'}).timeout(Duration(seconds: 4));
        print('  GET partial status: ${getResp.statusCode}');
      }
    } catch (e) {
      print('  Error: $e');
    }
  }

  final pipedInstances = [
    'https://pipedapi.in.projectsegfau.lt',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.sny.rip',
    'https://api.piped.yt',
  ];

  print('\n--- Testing Piped /streams/ endpoint ---');
  for (final base in pipedInstances) {
    final url = '$base/streams/$videoId';
    print('Testing Piped API: $url');
    try {
      final resp = await http.get(Uri.parse(url)).timeout(Duration(seconds: 6));
      print('  Status Code: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data.containsKey('audioStreams')) {
          final audioStreams = data['audioStreams'] as List;
          print('  Found ${audioStreams.length} audio streams in Piped!');
          if (audioStreams.isNotEmpty) {
            final firstStreamUrl = audioStreams.first['url'] as String;
            print('  Candidate stream URL: ${firstStreamUrl.substring(0, 100)}...');
            // Verificar si el stream es reproducible (HEAD o GET parcial)
            final checkResp = await http.head(Uri.parse(firstStreamUrl)).timeout(Duration(seconds: 4));
            print('    HEAD check on Piped stream URL: ${checkResp.statusCode}');
            if (checkResp.statusCode != 403) {
              print('    ✓ Piped stream is accessible!');
            }
          }
        }
      }
    } catch (e) {
      print('  Error: $e');
    }
  }
}
