import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  print('==================================================');
  print('Iniciando Test de Extracción de Audio de YouTube');
  print('==================================================');

  // Lista de 3 vídeos ultra populares y estables (nunca deberían borrarse)
  final testVideos = [
    {'id': 'dQw4w9WgXcQ', 'name': 'Rick Astley - Never Gonna Give You Up'},
    {'id': '9bZkp7q19f0', 'name': 'PSY - Gangnam Style'},
    {'id': 'kJQP7kiw5Fk', 'name': 'Luis Fonsi - Despacito'},
  ];

  final yt = YoutubeExplode();
  int successCount = 0;

  for (final video in testVideos) {
    final videoId = video['id']!;
    final videoName = video['name']!;
    print('\n[Probando] $videoName (ID: $videoId)...');

    bool videoSuccess = false;
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // 1. Obtener metadatos del vídeo
        final videoMeta = await yt.videos.get(videoId);
        print('  - Título obtenido: "${videoMeta.title}"');

        // 2. Obtener el manifiesto de streams
        final manifest = await yt.videos.streamsClient.getManifest(videoId);
        
        // 3. Buscar el stream de solo audio con mayor bitrate
        final audioStream = manifest.audioOnly.withHighestBitrate();
        
        if (audioStream.url.toString().isNotEmpty) {
          print('  - URL de streaming de audio extraída con éxito!');
          print('  - Bitrate: ${audioStream.bitrate}');
          videoSuccess = true;
          successCount++;
          break; // Salir del bucle de reintentos
        } else {
          throw Exception('La URL de audio obtenida está vacía.');
        }
      } catch (e) {
        print('  - [Intento $attempt/$maxRetries fallido]: $e');
        if (attempt < maxRetries) {
          // Esperar un segundo antes de reintentar por si fue un micro-corte de red
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    if (videoSuccess) {
      print('  -> Resultado: OK');
    } else {
      print('  -> Resultado: ERROR (Agotados los $maxRetries intentos)');
    }
  }

  // Cerrar el cliente de YouTube Explode para liberar sockets
  yt.close();

  print('\n==================================================');
  print('Resumen de Resultados: $successCount de ${testVideos.length} vídeos extraídos con éxito.');
  print('==================================================');

  // Si al menos un vídeo se pudo extraer con éxito, el reproductor de YouTube
  // sigue funcionando (el código interno de la web es compatible).
  if (successCount > 0) {
    print('TEST EXITOSO: La extracción de streams funciona correctamente. exit(0)');
    exit(0);
  } else {
    print('TEST FALLIDO: No se pudo extraer audio de ningún vídeo. YouTube puede haber cambiado su estructura. exit(1)');
    exit(1);
  }
}
