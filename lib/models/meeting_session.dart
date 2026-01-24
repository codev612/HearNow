import 'transcript_bubble.dart';
import 'meeting_mode.dart';

class MeetingSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<TranscriptBubble> bubbles;
  final String? summary;
  final String? insights;
  final String? questions;
  final MeetingMode mode;
  final Map<String, dynamic> metadata;

  MeetingSession({
    required this.id,
    required this.title,
    required this.createdAt,
    this.updatedAt,
    required this.bubbles,
    this.summary,
    this.insights,
    this.questions,
    this.mode = MeetingMode.general,
    this.metadata = const {},
  });

  MeetingSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<TranscriptBubble>? bubbles,
    String? summary,
    String? insights,
    String? questions,
    MeetingMode? mode,
    Map<String, dynamic>? metadata,
  }) {
    return MeetingSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      bubbles: bubbles ?? this.bubbles,
      summary: summary ?? this.summary,
      insights: insights ?? this.insights,
      questions: questions ?? this.questions,
      mode: mode ?? this.mode,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'bubbles': bubbles.map((b) => {
            'source': b.source.toString().split('.').last,
            'text': b.text,
            'timestamp': b.timestamp.toIso8601String(),
            'isDraft': b.isDraft,
          }).toList(),
      'summary': summary,
      'insights': insights,
      'questions': questions,
      'mode': mode.name,
      'metadata': metadata,
    };
  }

  factory MeetingSession.fromJson(Map<String, dynamic> json) {
    TranscriptSource sourceFromString(String s) {
      return switch (s) {
        'mic' => TranscriptSource.mic,
        'system' => TranscriptSource.system,
        _ => TranscriptSource.unknown,
      };
    }

    // Parse dates and convert to local time if they're in UTC
    final createdAtParsed = DateTime.parse(json['createdAt'] as String);
    final createdAt = createdAtParsed.isUtc ? createdAtParsed.toLocal() : createdAtParsed;
    
    DateTime? updatedAt;
    if (json['updatedAt'] != null) {
      final updatedAtParsed = DateTime.parse(json['updatedAt'] as String);
      updatedAt = updatedAtParsed.isUtc ? updatedAtParsed.toLocal() : updatedAtParsed;
    }

    return MeetingSession(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: createdAt,
      updatedAt: updatedAt,
      bubbles: (json['bubbles'] as List<dynamic>)
          .map((b) {
            final timestampParsed = DateTime.parse(b['timestamp'] as String);
            final timestamp = timestampParsed.isUtc ? timestampParsed.toLocal() : timestampParsed;
            return TranscriptBubble(
              source: sourceFromString(b['source'] as String),
              text: b['text'] as String,
              timestamp: timestamp,
              isDraft: b['isDraft'] as bool? ?? false,
            );
          })
          .toList(),
      summary: json['summary'] as String?,
      insights: json['insights'] as String?,
      questions: json['questions'] as String?,
      mode: MeetingMode.fromString(json['mode'] as String?),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  String get fullTranscript {
    return bubbles
        .where((b) => !b.isDraft)
        .map((b) => '${b.source.toString().split('.').last.toUpperCase()}: ${b.text}')
        .join('\n\n');
  }

  Duration get duration {
    if (bubbles.isEmpty) return Duration.zero;
    final first = bubbles.first.timestamp;
    final last = bubbles.last.timestamp;
    return last.difference(first);
  }
}
