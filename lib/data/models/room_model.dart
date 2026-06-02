import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de datos que representa una Sala de Música en Firestore.
class RoomModel {
  final String id; // Generalmente el código de 4 dígitos generado aleatoriamente
  final String hostId; // ID del dispositivo u usuario Host
  final bool isPlaying; // Indica si la música se está reproduciendo actualmente
  final String currentPlatform; // 'spotify' o 'youtube'
  final DateTime createdAt;

  RoomModel({
    required this.id,
    required this.hostId,
    required this.isPlaying,
    required this.currentPlatform,
    required this.createdAt,
  });

  /// Factory para construir el modelo a partir del mapa proveniente de Firestore.
  factory RoomModel.fromMap(Map<String, dynamic> map, String documentId) {
    return RoomModel(
      id: documentId,
      hostId: map['hostId'] as String? ?? '',
      isPlaying: map['isPlaying'] as bool? ?? false,
      currentPlatform: map['currentPlatform'] as String? ?? 'youtube',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convierte el objeto a un mapa persistible en Firestore.
  Map<String, dynamic> toMap() {
    return {
      'hostId': hostId,
      'isPlaying': isPlaying,
      'currentPlatform': currentPlatform,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Genera una copia modificada del modelo
  RoomModel copyWith({
    String? id,
    String? hostId,
    bool? isPlaying,
    String? currentPlatform,
    DateTime? createdAt,
  }) {
    return RoomModel(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      isPlaying: isPlaying ?? this.isPlaying,
      currentPlatform: currentPlatform ?? this.currentPlatform,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
