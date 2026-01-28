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
    final tokenChanged = _authToken != token;
    _authToken = token;
    // Only disconnect if token actually changed (not just set for the first time)
    if (tokenChanged && _aiChannel != null) {
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

    print('[AiService] Connecting to AI WebSocket: $wsUrl');
    _aiChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    print('[AiService] AI WebSocket connected');
    _aiSub = _aiChannel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          if (data is! Map<String, dynamic>) {
            print('[AiService] Received non-map message: $message');
            return;
          }

          final type = data['type']?.toString() ?? '';
          final requestId = data['requestId']?.toString() ?? '';
          
          // Handle ai_start message (has requestId but is just a notification)
          if (type == 'ai_start') {
            print('[AiService] Received ai_start for request $requestId');
            // Don't need to do anything, just wait for deltas
            return;
          }

          // All other messages should have a requestId
          if (requestId.isEmpty) {
            print('[AiService] Received message without requestId: type=$type, data=$data');
            return;
          }

          final ctrl = _streams[requestId];
          if (ctrl == null) {
            print('[AiService] Received message for unknown requestId: $requestId, type=$type');
            return;
          }

          if (type == 'ai_delta') {
            final delta = data['delta']?.toString() ?? '';
            if (delta.isNotEmpty) {
              ctrl.add(delta);
            }
            return;
          }
          if (type == 'ai_done') {
            print('[AiService] Received ai_done for request $requestId');
            ctrl.close();
            _streams.remove(requestId);
            return;
          }
          if (type == 'ai_error') {
            final msg = data['message']?.toString() ?? 'AI error';
            print('[AiService] AI error for request $requestId: $msg');
            ctrl.addError(msg);
            ctrl.close();
            _streams.remove(requestId);
            return;
          }
          
          print('[AiService] Unknown message type: $type for request $requestId');
        } catch (e) {
          // Log parse errors but don't disconnect
          print('[AiService] Error parsing message: $e, message: $message');
        }
      },
      onError: (e) {
        print('[AiService] WebSocket error: $e');
        // Only disconnect if it's a critical error
        // Don't disconnect on transient errors - let the connection retry
        for (final ctrl in _streams.values) {
          if (!ctrl.isClosed) {
            ctrl.addError(e);
            ctrl.close();
          }
        }
        _streams.clear();
        // Don't disconnect immediately - let it retry on next request
        // disconnectAi();
      },
      onDone: () {
        print('[AiService] WebSocket connection closed (onDone)');
        // Connection closed - clear streams but don't disconnect (already closed)
        for (final ctrl in _streams.values) {
          if (!ctrl.isClosed) {
            ctrl.addError('AI connection closed');
            ctrl.close();
          }
        }
        _streams.clear();
        // Reset channel so it can reconnect on next request
        _aiSub = null;
        _aiChannel = null;
      },
    );
  }

  /// Stream AI tokens from the backend over WebSocket.
  /// Emits token deltas as they arrive.
  Stream<String> streamRespond({
    required List<Map<String, String>> turns,
    String? question,
    String mode = 'reply',
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 60),
  }) {
    if (aiWsUrl == null) {
      return Stream.error('AI WebSocket not configured');
    }

    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final controller = StreamController<String>();
    _streams[requestId] = controller;

    () async {
      try {
        print('[AiService] streamRespond: mode=$mode, requestId=$requestId, turns=${turns.length}');
        await _ensureAiConnected();
        
        if (_aiChannel == null) {
          print('[AiService] Failed to establish connection, falling back to HTTP');
          final ctrl = _streams.remove(requestId);
          if (ctrl != null && !ctrl.isClosed) {
            ctrl.addError('Failed to establish AI connection');
            ctrl.close();
          }
          return;
        }

        final payload = <String, dynamic>{
          'type': 'ai_request',
          'requestId': requestId,
          'mode': mode,
          'turns': turns,
        };

        final q = question?.trim() ?? '';
        if (q.isNotEmpty) payload['question'] = q;
        
        final prompt = systemPrompt?.trim() ?? '';
        if (prompt.isNotEmpty) payload['systemPrompt'] = prompt;

        print('[AiService] Sending ai_request: mode=$mode, requestId=$requestId');
        try {
          _aiChannel!.sink.add(jsonEncode(payload));
          print('[AiService] Request sent successfully');
        } catch (e) {
          // Connection might be closed, reset it
          print('[AiService] Error sending request, resetting connection: $e');
          _aiChannel = null;
          _aiSub = null;
          final ctrl = _streams.remove(requestId);
          if (ctrl != null && !ctrl.isClosed) {
            ctrl.addError('Connection lost, please try again');
            ctrl.close();
          }
        }

        // Timeout protection
        Future.delayed(timeout, () {
          final ctrl = _streams.remove(requestId);
          if (ctrl != null && !ctrl.isClosed) {
            print('[AiService] Request $requestId timed out after ${timeout.inSeconds}s');
            try {
              _aiChannel?.sink.add(jsonEncode({'type': 'ai_cancel', 'requestId': requestId}));
            } catch (_) {}
            ctrl.addError('AI request timed out');
            ctrl.close();
          }
        });
      } catch (e, stackTrace) {
        print('[AiService] Error in streamRespond setup: $e');
        print('[AiService] Stack trace: $stackTrace');
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
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (aiWsUrl != null) {
      final buffer = StringBuffer();
      try {
        await for (final delta in streamRespond(
          turns: turns,
          question: question,
          mode: mode,
          systemPrompt: systemPrompt,
          timeout: timeout,
        )) {
          buffer.write(delta);
        }
        final result = buffer.toString().trim();
        if (result.isEmpty) {
          throw Exception('AI response was empty');
        }
        return result;
      } catch (e) {
        print('[AiService] Error in streamRespond for mode=$mode: $e');
        // If WebSocket fails, fall back to HTTP
        print('[AiService] Falling back to HTTP for mode=$mode');
      }
    }

    final uri = Uri.parse(httpBaseUrl).resolve('/ai/respond');
    final payload = <String, dynamic>{'mode': mode, 'turns': turns};

    final q = question?.trim() ?? '';
    if (q.isNotEmpty) payload['question'] = q;
    
    final prompt = systemPrompt?.trim() ?? '';
    if (prompt.isNotEmpty) payload['systemPrompt'] = prompt;

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
    Duration timeout = const Duration(seconds: 60),
  }) =>
      respond(turns: turns, mode: 'summary', timeout: timeout);

  Future<String> generateInsights({
    required List<Map<String, String>> turns,
    Duration timeout = const Duration(seconds: 60),
  }) =>
      respond(turns: turns, mode: 'insights', timeout: timeout);

  Future<String> generateQuestions({
    required List<Map<String, String>> turns,
    Duration timeout = const Duration(seconds: 60),
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
