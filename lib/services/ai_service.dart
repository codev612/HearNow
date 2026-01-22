import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// AI client that can call the backend via HTTP or via WebSocket streaming.
class AiService {
  final String httpBaseUrl;

  /// If provided, AI calls will prefer streaming over WebSocket to this URL.
  /// Example: `ws://localhost:3000/ai`
  final String? aiWsUrl;

  String? _authToken;
  WebSocketChannel? _aiChannel;
  StreamSubscription? _aiSub;
  final Map<String, StreamController<String>> _streams = {};

  AiService({required this.httpBaseUrl, this.aiWsUrl, String? authToken}) : _authToken = authToken;

  void setAuthToken(String? token) {
    _authToken = token;
    // Disconnect existing connection if token changes
    if (_aiChannel != null) {
      disconnectAi();
    }
  }

  Future<void> _ensureAiConnected() async {
    if (aiWsUrl == null) return;
    if (_aiChannel != null) return;
    if (_authToken == null || _authToken!.isEmpty) {
      throw Exception('Authentication required');
    }

    // Build WebSocket URL with auth token
    var wsUrl = aiWsUrl!;
    final uri = Uri.parse(wsUrl);
    wsUrl = uri.replace(queryParameters: {
      ...uri.queryParameters,
      'token': _authToken!,
    }).toString();

    _aiChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _aiSub = _aiChannel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          if (data is! Map<String, dynamic>) return;

          final type = data['type']?.toString() ?? '';
          final requestId = data['requestId']?.toString() ?? '';
          if (requestId.isEmpty) return;

          final ctrl = _streams[requestId];
          if (ctrl == null) return;

          if (type == 'ai_delta') {
            final delta = data['delta']?.toString() ?? '';
            if (delta.isNotEmpty) ctrl.add(delta);
            return;
          }
          if (type == 'ai_done') {
            ctrl.close();
            _streams.remove(requestId);
            return;
          }
          if (type == 'ai_error') {
            final msg = data['message']?.toString() ?? 'AI error';
            ctrl.addError(msg);
            ctrl.close();
            _streams.remove(requestId);
            return;
          }
        } catch (_) {}
      },
      onError: (e) {
        for (final ctrl in _streams.values) {
          ctrl.addError(e);
          ctrl.close();
        }
        _streams.clear();
        disconnectAi();
      },
      onDone: () {
        for (final ctrl in _streams.values) {
          ctrl.addError('AI connection closed');
          ctrl.close();
        }
        _streams.clear();
        disconnectAi();
      },
    );
  }

  /// Stream AI tokens from the backend over WebSocket.
  /// Emits token deltas as they arrive.
  Stream<String> streamRespond({
    required List<Map<String, String>> turns,
    String? question,
    String mode = 'reply',
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (aiWsUrl == null) {
      return Stream.error('AI WebSocket not configured');
    }

    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final controller = StreamController<String>();
    _streams[requestId] = controller;

    () async {
      try {
        await _ensureAiConnected();

        final payload = <String, dynamic>{
          'type': 'ai_request',
          'requestId': requestId,
          'mode': mode,
          'turns': turns,
        };

        final q = question?.trim() ?? '';
        if (q.isNotEmpty) payload['question'] = q;

        _aiChannel?.sink.add(jsonEncode(payload));

        // Timeout protection
        Future.delayed(timeout, () {
          final ctrl = _streams.remove(requestId);
          if (ctrl != null && !ctrl.isClosed) {
            try {
              _aiChannel?.sink.add(jsonEncode({'type': 'ai_cancel', 'requestId': requestId}));
            } catch (_) {}
            ctrl.addError('AI request timed out');
            ctrl.close();
          }
        });
      } catch (e) {
        final ctrl = _streams.remove(requestId);
        if (ctrl != null && !ctrl.isClosed) {
          ctrl.addError(e);
          ctrl.close();
        }
      }
    }();

    return controller.stream;
  }

  /// Non-streaming response (string). If WS is configured, we stream and aggregate.
  Future<String> respond({
    required List<Map<String, String>> turns,
    String? question,
    String mode = 'reply',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (aiWsUrl != null) {
      final buffer = StringBuffer();
      await for (final delta in streamRespond(
        turns: turns,
        question: question,
        mode: mode,
        timeout: timeout,
      )) {
        buffer.write(delta);
      }
      return buffer.toString().trim();
    }

    final uri = Uri.parse(httpBaseUrl).resolve('/ai/respond');
    final payload = <String, dynamic>{'mode': mode, 'turns': turns};

    final q = question?.trim() ?? '';
    if (q.isNotEmpty) payload['question'] = q;

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final data = jsonDecode(response.body);
        final error = data is Map<String, dynamic> ? (data['error']?.toString() ?? '') : '';
        throw Exception(error.isNotEmpty ? error : 'HTTP ${response.statusCode}');
      } catch (_) {
        throw Exception('HTTP ${response.statusCode}');
      }
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) throw Exception('Unexpected response');
    return (data['text']?.toString() ?? '').trim();
  }

  Future<String> generateSummary({
    required List<Map<String, String>> turns,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      respond(turns: turns, mode: 'summary', timeout: timeout);

  Future<String> generateInsights({
    required List<Map<String, String>> turns,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      respond(turns: turns, mode: 'insights', timeout: timeout);

  Future<String> generateQuestions({
    required List<Map<String, String>> turns,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      respond(turns: turns, mode: 'questions', timeout: timeout);

  void disconnectAi() {
    try {
      _aiSub?.cancel();
    } catch (_) {}
    _aiSub = null;
    try {
      _aiChannel?.sink.close();
    } catch (_) {}
    _aiChannel = null;
  }

  void dispose() {
    disconnectAi();
    for (final ctrl in _streams.values) {
      if (!ctrl.isClosed) ctrl.close();
    }
    _streams.clear();
  }
}
