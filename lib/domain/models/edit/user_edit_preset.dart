import 'dart:convert';

import 'edit_operation.dart';

/// A user-created edit preset — a named collection of operations that
/// can be saved, loaded, and applied to any photo.
class UserEditPreset {
  final String id;
  final String name;
  final List<EditOperation> operations;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? thumbnailPhotoId;

  const UserEditPreset({
    required this.id,
    required this.name,
    required this.operations,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailPhotoId,
  });

  /// Whether the preset has any meaningful operations.
  bool get isEmpty => operations.isEmpty || operations.every((op) => op.isNoOp);

  /// Brief summary of what the preset does.
  String get summary {
    if (isEmpty) return 'Empty preset';
    final parts = <String>[];
    for (final op in operations) {
      if (op.isNoOp) continue;
      final label = op.aiSummary;
      if (label.isNotEmpty) {
        parts.add(label);
      } else if (op.isAdjustment) {
        final activeCount = op.adjustmentValues.values
            .where((v) => v != 0.0)
            .length;
        parts.add('$activeCount adj');
      }
    }
    return parts.isEmpty ? 'Empty preset' : parts.join(', ');
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'operations': operations.map((op) => op.toMap()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'thumbnail_photo_id': thumbnailPhotoId,
      };

  factory UserEditPreset.fromMap(Map<String, dynamic> map) => UserEditPreset(
        id: map['id'] as String,
        name: map['name'] as String,
        operations: (map['operations'] as List)
            .map((e) => EditOperation.fromMap(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        thumbnailPhotoId: map['thumbnail_photo_id'] as String?,
      );

  /// Serialize to JSON string for database storage.
  String toJson() => jsonEncode(toMap());

  /// Deserialize from JSON string.
  factory UserEditPreset.fromJson(String json) =>
      UserEditPreset.fromMap(jsonDecode(json) as Map<String, dynamic>);

  UserEditPreset copyWith({
    String? id,
    String? name,
    List<EditOperation>? operations,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? thumbnailPhotoId,
  }) {
    return UserEditPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      operations: operations ?? this.operations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      thumbnailPhotoId: thumbnailPhotoId ?? this.thumbnailPhotoId,
    );
  }
}
