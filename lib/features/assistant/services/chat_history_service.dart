import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gallery_intent.dart';

/// A single persisted chat message.
class ChatMessage {
  final bool isUser;
  final String text;
  final List<String> photoIds;
  final GalleryIntent? intent;
  final DateTime timestamp;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.photoIds = const [],
    this.intent,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'isUser': isUser,
        'text': text,
        'photoIds': photoIds,
        'intent': intent?.name,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      isUser: json['isUser'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      photoIds: (json['photoIds'] as List?)?.cast<String>() ?? [],
      intent: json['intent'] != null
          ? GalleryIntent.values.firstWhere(
              (e) => e.name == json['intent'],
              orElse: () => GalleryIntent.unknown,
            )
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}

/// Persists chat history across app sessions.
///
/// Stores the last [maxMessages] messages in SharedPreferences.
/// Privacy-first: messages are stored locally only, never uploaded.
class ChatHistoryService {
  static const _key = 'assistant_chat_history';
  static const _maxMessages = 100;
  static const _maxAge = Duration(days: 7);

  final SharedPreferences _prefs;

  ChatHistoryService(this._prefs);

  /// Load persisted chat messages.
  List<ChatMessage> loadMessages() {
    final json = _prefs.getString(_key);
    if (json == null) return [];

    try {
      final list = (jsonDecode(json) as List)
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList();

      // Filter out messages older than _maxAge
      final cutoff = DateTime.now().subtract(_maxAge);
      final filtered = list.where((m) => m.timestamp.isAfter(cutoff)).toList();

      // Keep only the last _maxMessages
      if (filtered.length > _maxMessages) {
        return filtered.sublist(filtered.length - _maxMessages);
      }

      return filtered;
    } catch (_) {
      return [];
    }
  }

  /// Save chat messages to persistence.
  Future<void> saveMessages(List<ChatMessage> messages) async {
    // Keep only the last _maxMessages
    final toSave = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;

    final json = jsonEncode(toSave.map((m) => m.toJson()).toList());
    await _prefs.setString(_key, json);
  }

  /// Append a single message and persist.
  Future<void> appendMessage(ChatMessage message) async {
    final messages = loadMessages();
    messages.add(message);
    await saveMessages(messages);
  }

  /// Clear all persisted chat history.
  Future<void> clearHistory() async {
    await _prefs.remove(_key);
  }
}
