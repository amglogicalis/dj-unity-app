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
    final sub1 = playerStream.listen((value) {
      final PlayerState playerState = value.playerState;
      if (playerState == PlayerState.ended) {
        // ended
      }
    });

    final sub2 = controller.videoStateStream.listen((state) {
      // state updated
    });

    // Verify playVideo, pauseVideo and loadVideoById compile
    controller.playVideo();
    controller.pauseVideo();
    controller.loadVideoById(videoId: 'yKNxeF4KMsY');

    expect(controller, isNotNull);

    await sub1.cancel();
    await sub2.cancel();
  });
}
