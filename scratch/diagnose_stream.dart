import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final videoId = 'dQw4w9WgXcQ'; // Rick Astley - Never Gonna Give You Up (Ultra estable)
  print('Diagnosing Video ID: $videoId');

  final yt = YoutubeExplode();
  try {
    print('Fetching manifest using YoutubeApiClient.ios...');
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [
        YoutubeApiClient.ios,
        YoutubeApiClient.mweb,
        YoutubeApiClient.tv,
      ],
    ).timeout(Duration(seconds: 10));

    final audioStreams = manifest.audioOnly.toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    print('Found ${audioStreams.length} audio streams.');

    if (audioStreams.isEmpty) {
      print('No audio streams found!');
      return;
    }

    final candidate = audioStreams.first.url.toString();
    print('\nTesting candidate URL:');
    print(candidate.substring(0, 120) + '...');

    // Test 1: HEAD sin headers
    print('\n--- Test 1: HEAD request (no headers) ---');
    try {
      final resp = await http.head(Uri.parse(candidate)).timeout(Duration(seconds: 4));
      print('Status Code: ${resp.statusCode}');
      print('Response headers: ${resp.headers}');
    } catch (e) {
      print('Error on Test 1: $e');
    }

    // Test 2: HEAD con User-Agent de iOS
    print('\n--- Test 2: HEAD request (iOS User-Agent) ---');
    try {
      final resp = await http.head(
        Uri.parse(candidate),
        headers: {
          'User-Agent': 'com.google.ios.youtube/19.17.2 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X; en_US)',
        },
      ).timeout(Duration(seconds: 4));
      print('Status Code: ${resp.statusCode}');
      print('Response headers: ${resp.headers}');
    } catch (e) {
      print('Error on Test 2: $e');
    }

    // Test 3: GET parcial (Range bytes=0-10) sin headers
    print('\n--- Test 3: GET request (Range bytes=0-10, no headers) ---');
    try {
      final resp = await http.get(
        Uri.parse(candidate),
        headers: {
          'Range': 'bytes=0-10',
        },
      ).timeout(Duration(seconds: 4));
      print('Status Code: ${resp.statusCode}');
      print('Content-Length: ${resp.bodyBytes.length}');
      print('Response headers: ${resp.headers}');
    } catch (e) {
      print('Error on Test 3: $e');
    }

    // Test 4: GET parcial (Range bytes=0-10) con User-Agent de iOS
    print('\n--- Test 4: GET request (Range bytes=0-10, iOS User-Agent) ---');
    try {
      final resp = await http.get(
        Uri.parse(candidate),
        headers: {
          'Range': 'bytes=0-10',
          'User-Agent': 'com.google.ios.youtube/19.17.2 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X; en_US)',
        },
      ).timeout(Duration(seconds: 4));
      print('Status Code: ${resp.statusCode}');
      print('Content-Length: ${resp.bodyBytes.length}');
      print('Response headers: ${resp.headers}');
    } catch (e) {
      print('Error on Test 4: $e');
    }

  } catch (e) {
    print('General error: $e');
  } finally {
    yt.close();
  }
}
