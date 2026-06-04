import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final videoId = 'TWsq3QPv_Oc'; // Ozuna - Luz Apaga (the one from user log)
  print('Testing Video ID: $videoId\n');

  final yt = YoutubeExplode();
  final clients = {
    'androidSdkless': YoutubeApiClient.androidSdkless,
    'android': YoutubeApiClient.android,
    'androidVr': YoutubeApiClient.androidVr,
    'webCreator': YoutubeApiClient.webCreator,
    'ios': YoutubeApiClient.ios,
    'tv': YoutubeApiClient.tv,
    'mweb': YoutubeApiClient.mweb,
  };

  final userAgents = {
    'none': null,
    'chrome_mobile': 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/95.0.4638.50 Mobile Safari/537.36',
    'exoplayer_default': 'ExoPlayerDemo/1.0.0 (Linux; Android 11) AndroidXMedia3/1.4.1',
    'youtube_android_app': 'com.google.android.youtube/19.12.35 (Linux; U; Android 11; Build/RP1A.200720.011) Version/19.12.35',
    'youtube_ios_app': 'com.google.ios.youtube/19.17.2 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X; en_US)',
  };

  for (final clientEntry in clients.entries) {
    final clientName = clientEntry.key;
    final client = clientEntry.value;

    print('==================================================');
    print('Testing Client: $clientName');
    print('==================================================');

    try {
      final manifest = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [client],
      ).timeout(Duration(seconds: 8));

      final audioStreams = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      
      if (audioStreams.isEmpty) {
        print('  No audio streams found for $clientName.');
        continue;
      }

      print('  Found ${audioStreams.length} audio streams.');
      final candidateUrl = audioStreams.first.url.toString();
      print('  Stream Codec: ${audioStreams.first.audioCodec}, Bitrate: ${audioStreams.first.bitrate}');

      for (final uaEntry in userAgents.entries) {
        final uaName = uaEntry.key;
        final uaValue = uaEntry.value;

        final headers = <String, String>{
          'Range': 'bytes=0-10',
        };
        if (uaValue != null) {
          headers['User-Agent'] = uaValue;
        }

        try {
          final resp = await http.get(
            Uri.parse(candidateUrl),
            headers: headers,
          ).timeout(Duration(seconds: 4));

          print('    - User-Agent [$uaName] -> Status: ${resp.statusCode} (Bytes: ${resp.bodyBytes.length})');
        } catch (e) {
          print('    - User-Agent [$uaName] -> Exception: $e');
        }
      }
    } catch (e) {
      print('  Failed to fetch manifest for $clientName: $e');
    }
    print('');
  }

  yt.close();
}
