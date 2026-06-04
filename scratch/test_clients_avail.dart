import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  // Let's print out if we can inspect YoutubeApiClient or see what fields it has.
  // We can also try getting a video and printing its stream clients.
  print('YoutubeApiClient properties:');
  // We can try to use reflection or just check compile-time constants by checking if they compile:
  final list = [
    YoutubeApiClient.android,
    YoutubeApiClient.androidVr,
    YoutubeApiClient.androidSdkless,
    YoutubeApiClient.ios,
    YoutubeApiClient.mweb,
    YoutubeApiClient.tv,
    YoutubeApiClient.web,
    YoutubeApiClient.webCreator,
    YoutubeApiClient.webEmbedded,
  ];
  print('Available clients compiled successfully: $list');
}
