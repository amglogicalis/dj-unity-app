import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de datos que representa una canción en la cola de reproducción de Firestore.
class SongModel {
  final String id;
  final String title;
  final String artist;
  final String platform; // 'spotify' o 'youtube'
  final String videoOrTrackId;
  final int duration; // Duración en segundos
  final String addedBy; // Nombre o ID del invitado que la añadió
  final DateTime createdAt;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.platform,
    required this.videoOrTrackId,
    required this.duration,
    required this.addedBy,
    required this.createdAt,
  });

  /// Factory para construir el modelo desde un documento de Firestore.
  factory SongModel.fromMap(Map<String, dynamic> map, String documentId) {
    return SongModel(
      id: documentId,
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? 'Artista Desconocido',
      platform: map['platform'] as String? ?? 'youtube',
      videoOrTrackId: map['videoOrTrackId'] as String? ?? '',
      duration: map['duration'] as int? ?? 0,
      addedBy: map['addedBy'] as String? ?? 'Anónimo',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convierte el modelo a un Map estructurado para Firestore.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'artist': artist,
      'platform': platform,
      'videoOrTrackId': videoOrTrackId,
      'duration': duration,
      'addedBy': addedBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Genera una copia modificada del modelo
  SongModel copyWith({
    String? id,
    String? title,
    String? artist,
    String? platform,
    String? videoOrTrackId,
    int? duration,
    String? addedBy,
    DateTime? createdAt,
  }) {
    return SongModel(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      platform: platform ?? this.platform,
      videoOrTrackId: videoOrTrackId ?? this.videoOrTrackId,
      duration: duration ?? this.duration,
      addedBy: addedBy ?? this.addedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
