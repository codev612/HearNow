import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io' show Platform;
import '../services/transcription_service.dart';
import '../services/audio_capture_service.dart';
import '../services/windows_audio_service.dart';

class SpeechToTextProvider extends ChangeNotifier {
  TranscriptionService? _transcriptionService;
  AudioCaptureService? _audioCaptureService;
  Timer? _mockAudioTimer;
  Timer? _systemAudioPollTimer;
  final List<int> _systemAudioBuffer = <int>[];
  bool _isSystemAudioCapturing = false;
  
  bool _isRecording = false;
  bool _isConnected = false;
  String _transcriptText = '';
  String _interimText = '';
  String _errorMessage = '';
  int _audioFrameCount = 0;

  bool get isRecording => _isRecording;
  bool get isConnected => _isConnected;
  String get transcriptText => _transcriptText;
  String get interimText => _interimText;
  String get errorMessage => _errorMessage;

  String _appendFinalWithOverlap(String existing, String next) {
    final nextTrimmed = next.trim();
    if (nextTrimmed.isEmpty) return existing;

    var existingTrimmed = existing.trimRight();
    if (existingTrimmed.isEmpty) {
      return '$nextTrimmed ';
    }

    // If already present at the end, don't append.
    if (existingTrimmed.endsWith(nextTrimmed)) {
      return existingTrimmed + (existing.endsWith(' ') ? '' : ' ');
    }

    // Compute overlap using only a tail window to keep it fast.
    const tailWindow = 200;
    final tail = existingTrimmed.substring(
      existingTrimmed.length > tailWindow ? existingTrimmed.length - tailWindow : 0,
    );

    final tailLower = tail.toLowerCase();
    final nextLower = nextTrimmed.toLowerCase();
    final maxOverlap = tailLower.length < nextLower.length ? tailLower.length : nextLower.length;

    var overlap = 0;
    for (var i = 1; i <= maxOverlap; i++) {
      if (tailLower.substring(tailLower.length - i) == nextLower.substring(0, i)) {
        overlap = i;
      }
    }

    final toAppend = nextTrimmed.substring(overlap);
    final needsSpace = existingTrimmed.isNotEmpty &&
        !existingTrimmed.endsWith(' ') &&
        !existingTrimmed.endsWith('\n');

    if (toAppend.isEmpty) {
      return existingTrimmed + (existing.endsWith(' ') ? '' : ' ');
    }

    return existingTrimmed + (needsSpace ? ' ' : '') + toAppend + ' ';
  }

  Future<bool> requestPermissions() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> initialize(String serverUrl) async {
    _transcriptionService = TranscriptionService(serverUrl: serverUrl);
    
    _transcriptionService!.transcriptStream.listen(
      (result) {
        if (result.isFinal) {
          _transcriptText = _appendFinalWithOverlap(_transcriptText, result.text);
          _interimText = '';
        } else {
          _interimText = result.text;
        }
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> startRecording() async {
    try {
      print('[SpeechToTextProvider] Starting recording...');
      _errorMessage = '';
      _audioFrameCount = 0;
      _systemAudioBuffer.clear();
      _isSystemAudioCapturing = false;
      
      // Request permissions
      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        _errorMessage = 'Microphone permission denied';
        print('[SpeechToTextProvider] Microphone permission denied');
        notifyListeners();
        return;
      }

      print('[SpeechToTextProvider] Permission granted, connecting to transcription service...');
      // Connect to WebSocket
      await _transcriptionService?.connect();
      _isConnected = true;

      // Start system audio capture on Windows (best-effort).
      if (!kIsWeb && Platform.isWindows) {
        final started = await WindowsAudioService.startSystemAudioCapture();
        _isSystemAudioCapturing = started;
        if (started) {
          _systemAudioPollTimer?.cancel();
          _systemAudioPollTimer = Timer.periodic(
            const Duration(milliseconds: 50),
            (_) {
              // Pull ~50ms at 16kHz mono PCM16 => 16000*0.05*2 = 1600 bytes
              WindowsAudioService.getSystemAudioFrame(lengthBytes: 1600).then((frame) {
                if (frame.isEmpty) return;
                _systemAudioBuffer.addAll(frame);
                // Cap buffer to ~2 seconds (64000 bytes)
                if (_systemAudioBuffer.length > 64000) {
                  _systemAudioBuffer.removeRange(0, _systemAudioBuffer.length - 64000);
                }
              });
            },
          );
        } else {
          print('[SpeechToTextProvider] System audio capture not available');
        }
      }

      // Initialize audio capture
      _audioCaptureService = AudioCaptureService(
        onAudioData: (audioData) {
          _audioFrameCount++;
          if (_audioFrameCount % 10 == 0) {
            print('[SpeechToTextProvider] Audio frame #$_audioFrameCount: ${audioData.length} bytes');
          }
          if (_isSystemAudioCapturing) {
            // Consume exactly the same number of bytes as mic chunk.
            final need = audioData.length;
            List<int> systemChunk;
            if (_systemAudioBuffer.length >= need) {
              systemChunk = _systemAudioBuffer.sublist(0, need);
              _systemAudioBuffer.removeRange(0, need);
            } else {
              // Not enough system audio yet; pad with zeros.
              systemChunk = List<int>.filled(need, 0);
              _systemAudioBuffer.clear();
            }

            final mixed = WindowsAudioService.mixAudio(audioData, systemChunk);
            _transcriptionService?.sendAudio(mixed);
          } else {
            _transcriptionService?.sendAudio(audioData);
          }
        },
      );

      // Request microphone permission and start capturing
      final canCapture = await _audioCaptureService!.requestPermissions();
      if (!canCapture) {
        _errorMessage = 'Microphone permission denied';
        _isConnected = false;
        _transcriptionService?.disconnect();
        notifyListeners();
        return;
      }

      // Start audio capturing
      try {
        await _audioCaptureService!.startCapturing();
      } catch (e) {
        _errorMessage = 'Failed to start audio capture: $e';
        _isConnected = false;
        _transcriptionService?.disconnect();
        notifyListeners();
        return;
      }

      _isRecording = true;
      notifyListeners();
      print('[SpeechToTextProvider] Recording started with real audio capture');
    } catch (e) {
      _errorMessage = 'Failed to start recording: $e';
      print('[SpeechToTextProvider] Error: $e');
      _isRecording = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    try {
      print('[SpeechToTextProvider] Stopping recording...');
      _mockAudioTimer?.cancel();
      _mockAudioTimer = null;

      _systemAudioPollTimer?.cancel();
      _systemAudioPollTimer = null;
      if (!kIsWeb && Platform.isWindows && _isSystemAudioCapturing) {
        await WindowsAudioService.stopSystemAudioCapture();
      }
      _isSystemAudioCapturing = false;
      _systemAudioBuffer.clear();
      
      // Stop audio capture
      await _audioCaptureService?.stopCapturing();
      _audioCaptureService?.dispose();
      _audioCaptureService = null;
      
      // Disconnect from transcription
      _transcriptionService?.disconnect();
      
      _isRecording = false;
      _isConnected = false;
      print('[SpeechToTextProvider] Recording stopped. Processed $_audioFrameCount audio frames');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to stop recording: $e';
      print('[SpeechToTextProvider] Error stopping: $e');
      notifyListeners();
    }
  }

  void clearTranscript() {
    _transcriptText = '';
    _interimText = '';
    _errorMessage = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _mockAudioTimer?.cancel();
    _audioCaptureService?.dispose();
    _transcriptionService?.dispose();
    super.dispose();
  }
}
