import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

void main() {
  testWidgets('Check YoutubePlayerController listener compilation', (WidgetTester tester) async {
    final controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showVideoAnnotations: false,
        showFullscreenButton: false,
        mute: false,
      ),
    );

    final Stream<YoutubePlayerValue> playerStream = controller.stream;
    playerStream.listen((value) {
      final PlayerState playerState = value.playerState;
      final Duration duration = value.metaData.duration;
      if (playerState == PlayerState.ended) {
        print('Ended');
      }
    });

    final streamSubscription = controller.videoStateStream.listen((state) {
      final Duration pos = state.position;
    });

    // Verify playVideo, pauseVideo and loadVideoById compile
    controller.playVideo();
    controller.pauseVideo();
    controller.loadVideoById(videoId: 'yKNxeF4KMsY');

    expect(controller, isNotNull);
  });
}
