import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/meeting_session.dart';

class MeetingStorageService {
  static const String _sessionsDir = 'meeting_sessions';

  Future<String> _getSessionsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final sessionsDir = Directory(path.join(appDir.path, _sessionsDir));
    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }
    return sessionsDir.path;
  }

  Future<String> _getSessionFilePath(String sessionId) async {
    final dir = await _getSessionsDirectory();
    return path.join(dir, '$sessionId.json');
  }

  Future<void> saveSession(MeetingSession session) async {
    try {
      final filePath = await _getSessionFilePath(session.id);
      final file = File(filePath);
      final json = jsonEncode(session.toJson());
      await file.writeAsString(json);
    } catch (e) {
      throw Exception('Failed to save session: $e');
    }
  }

  Future<MeetingSession?> loadSession(String sessionId) async {
    try {
      final filePath = await _getSessionFilePath(sessionId);
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      return MeetingSession.fromJson(data);
    } catch (e) {
      throw Exception('Failed to load session: $e');
    }
  }

  Future<List<MeetingSession>> listSessions() async {
    try {
      final dir = Directory(await _getSessionsDirectory());
      if (!await dir.exists()) {
        return [];
      }

      final files = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      final sessions = <MeetingSession>[];
      for (final file in files) {
        try {
          final json = await file.readAsString();
          final data = jsonDecode(json) as Map<String, dynamic>;
          sessions.add(MeetingSession.fromJson(data));
        } catch (e) {
          print('Error loading session from ${file.path}: $e');
        }
      }

      // Sort by updatedAt or createdAt descending
      sessions.sort((a, b) {
        final aTime = a.updatedAt ?? a.createdAt;
        final bTime = b.updatedAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      return sessions;
    } catch (e) {
      throw Exception('Failed to list sessions: $e');
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      final filePath = await _getSessionFilePath(sessionId);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw Exception('Failed to delete session: $e');
    }
  }

  Future<String> exportSessionAsText(MeetingSession session) async {
    final buffer = StringBuffer();
    buffer.writeln('Meeting Session: ${session.title}');
    buffer.writeln('Created: ${session.createdAt.toLocal()}');
    if (session.updatedAt != null) {
      buffer.writeln('Updated: ${session.updatedAt!.toLocal()}');
    }
    buffer.writeln('Duration: ${_formatDuration(session.duration)}');
    buffer.writeln('');
    buffer.writeln('=' * 60);
    buffer.writeln('');

    if (session.summary != null && session.summary!.isNotEmpty) {
      buffer.writeln('SUMMARY');
      buffer.writeln('-' * 60);
      buffer.writeln(session.summary);
      buffer.writeln('');
    }

    if (session.insights != null && session.insights!.isNotEmpty) {
      buffer.writeln('INSIGHTS');
      buffer.writeln('-' * 60);
      buffer.writeln(session.insights);
      buffer.writeln('');
    }

    final rawMarkers = session.metadata['markers'];
    if (rawMarkers is List && rawMarkers.isNotEmpty) {
      buffer.writeln('MARKERS');
      buffer.writeln('-' * 60);
      for (final item in rawMarkers) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final at = (m['at']?.toString() ?? '').trim();
        final label = (m['label']?.toString() ?? '').trim();
        final text = (m['text']?.toString() ?? '').trim();
        final source = (m['source']?.toString() ?? '').trim();
        final line = [
          if (at.isNotEmpty) at,
          if (source.isNotEmpty) '[$source]',
          if (label.isNotEmpty) label,
          if (text.isNotEmpty) '— $text',
        ].join(' ');
        if (line.trim().isNotEmpty) buffer.writeln('- $line');
      }
      buffer.writeln('');
    }

    buffer.writeln('TRANSCRIPT');
    buffer.writeln('-' * 60);
    buffer.writeln(session.fullTranscript);

    return buffer.toString();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
