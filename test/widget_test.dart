import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_music_room/main.dart';

void main() {
  testWidgets('Prueba de humo - Verificar título de inicio', (WidgetTester tester) async {
    // Construir nuestra app y disparar un frame.
    await tester.pumpWidget(const MusicRoomApp());

    // Verificar que el título principal de la app aparezca en pantalla.
    expect(find.text('HYBRID MUSIC ROOM'), findsOneWidget);
  });
}
