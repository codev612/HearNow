import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/meeting_session.dart';
import '../models/transcript_bubble.dart';
import '../services/meeting_storage_service.dart';
import '../services/ai_service.dart';

class MeetingProvider extends ChangeNotifier {
  final MeetingStorageService _storage = MeetingStorageService();
  AiService? _aiService;

  MeetingSession? _currentSession;
  List<MeetingSession> _sessions = [];
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isGeneratingSummary = false;
  bool _isGeneratingInsights = false;
  bool _isGeneratingQuestions = false;

  MeetingProvider({AiService? aiService}) : _aiService = aiService;

  void setAiService(AiService? aiService) {
    _aiService = aiService;
  }

  void updateAuthToken(String? token) {
    _aiService?.setAuthToken(token);
  }

  MeetingSession? get currentSession => _currentSession;
  List<MeetingSession> get sessions => List.unmodifiable(_sessions);
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isGeneratingSummary => _isGeneratingSummary;
  bool get isGeneratingInsights => _isGeneratingInsights;
  bool get isGeneratingQuestions => _isGeneratingQuestions;
  List<Map<String, dynamic>> get markers {
    final meta = _currentSession?.metadata ?? const <String, dynamic>{};
    final raw = meta['markers'];
    if (raw is List) {
      return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> loadSessions() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      _sessions = await _storage.listSessions();
    } catch (e) {
      _errorMessage = 'Failed to load sessions: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createNewSession({String? title}) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentSession = MeetingSession(
      id: sessionId,
      title: title ?? 'Meeting ${DateTime.now().toLocal().toString().substring(0, 16)}',
      createdAt: DateTime.now(),
      bubbles: [],
    );
    notifyListeners();
  }

  Future<void> saveCurrentSession({String? title}) async {
    if (_currentSession == null) return;

    try {
      _isLoading = true;
      _errorMessage = '';
      notifyListeners();

      final updated = _currentSession!.copyWith(
        title: title ?? _currentSession!.title,
        updatedAt: DateTime.now(),
      );
      await _storage.saveSession(updated);
      _currentSession = updated;
      await loadSessions();
    } catch (e) {
      _errorMessage = 'Failed to save session: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSession(String sessionId) async {
    try {
      _isLoading = true;
      _errorMessage = '';
      notifyListeners();

      final session = await _storage.loadSession(sessionId);
      if (session != null) {
        _currentSession = session;
      } else {
        _errorMessage = 'Session not found';
      }
    } catch (e) {
      _errorMessage = 'Failed to load session: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      _isLoading = true;
      _errorMessage = '';
      notifyListeners();

      await _storage.deleteSession(sessionId);
      if (_currentSession?.id == sessionId) {
        _currentSession = null;
      }
      await loadSessions();
    } catch (e) {
      _errorMessage = 'Failed to delete session: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateCurrentSessionBubbles(List<TranscriptBubble> bubbles) {
    if (_currentSession == null) return;

    _currentSession = _currentSession!.copyWith(
      bubbles: bubbles,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void addMarker(Map<String, dynamic> marker) {
    if (_currentSession == null) return;

    final meta = Map<String, dynamic>.from(_currentSession!.metadata);
    final existing = meta['markers'];
    final list = <Map<String, dynamic>>[];
    if (existing is List) {
      for (final item in existing) {
        if (item is Map) {
          list.add(Map<String, dynamic>.from(item));
        }
      }
    }
    list.add(Map<String, dynamic>.from(marker));
    meta['markers'] = list;

    _currentSession = _currentSession!.copyWith(
      metadata: meta,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> generateSummary() async {
    if (_currentSession == null || _aiService == null) return;
    if (_isGeneratingSummary) return;

    final bubbles = _currentSession!.bubbles.where((b) => !b.isDraft).toList();
    if (bubbles.isEmpty) {
      _errorMessage = 'No transcript to summarize';
      notifyListeners();
      return;
    }

    _isGeneratingSummary = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final turns = bubbles.map((b) => {
        'source': b.source.toString().split('.').last,
        'text': b.text,
      }).toList();

      final summary = await _aiService!.generateSummary(turns: turns);
      _currentSession = _currentSession!.copyWith(
        summary: summary,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      _errorMessage = 'Failed to generate summary: $e';
    } finally {
      _isGeneratingSummary = false;
      notifyListeners();
    }
  }

  Future<void> generateInsights() async {
    if (_currentSession == null || _aiService == null) return;
    if (_isGeneratingInsights) return;

    final bubbles = _currentSession!.bubbles.where((b) => !b.isDraft).toList();
    if (bubbles.isEmpty) {
      _errorMessage = 'No transcript to analyze';
      notifyListeners();
      return;
    }

    _isGeneratingInsights = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final turns = bubbles.map((b) => {
        'source': b.source.toString().split('.').last,
        'text': b.text,
      }).toList();

      final insights = await _aiService!.generateInsights(turns: turns);
      _currentSession = _currentSession!.copyWith(
        insights: insights,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      _errorMessage = 'Failed to generate insights: $e';
    } finally {
      _isGeneratingInsights = false;
      notifyListeners();
    }
  }

  Future<String> generateQuestions() async {
    if (_currentSession == null || _aiService == null) {
      return '';
    }
    if (_isGeneratingQuestions) return '';

    final bubbles = _currentSession!.bubbles.where((b) => !b.isDraft).toList();
    if (bubbles.isEmpty) {
      return '';
    }

    _isGeneratingQuestions = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final turns = bubbles.map((b) => {
        'source': b.source.toString().split('.').last,
        'text': b.text,
      }).toList();

      final questions = await _aiService!.generateQuestions(turns: turns);
      _isGeneratingQuestions = false;
      notifyListeners();
      return questions;
    } catch (e) {
      _errorMessage = 'Failed to generate questions: $e';
      _isGeneratingQuestions = false;
      notifyListeners();
      return '';
    }
  }

  Future<String> exportSessionAsText(String sessionId) async {
    try {
      final session = await _storage.loadSession(sessionId);
      if (session == null) {
        throw Exception('Session not found');
      }
      return await _storage.exportSessionAsText(session);
    } catch (e) {
      throw Exception('Failed to export session: $e');
    }
  }

  void clearCurrentSession() {
    _currentSession = null;
    notifyListeners();
  }
}
