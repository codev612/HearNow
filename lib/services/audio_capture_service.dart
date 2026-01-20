import 'dart:async';
import 'package:record/record.dart';

class AudioCaptureService {
  late final AudioRecorder _recorder;
  StreamSubscription? _audioSubscription;
  final Function(List<int>) onAudioData;

  AudioCaptureService({required this.onAudioData}) {
    _recorder = AudioRecorder();
  }

  Future<bool> requestPermissions() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (hasPermission == false) {
        print('[AudioCaptureService] No microphone permission');
        return false;
      }
      print('[AudioCaptureService] Microphone permission granted');
      return true;
    } catch (e) {
      print('[AudioCaptureService] Error requesting permissions: $e');
      return false;
    }
  }

  Future<void> startCapturing() async {
    try {
      print('[AudioCaptureService] Starting audio capture...');

      // Check if recorder is recording already
      final isRecording = await _recorder.isRecording();
      if (isRecording) {
        await _recorder.stop();
      }

      // Start recording microphone with streaming
      final recordStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 128000,
        ),
      );

      print('[AudioCaptureService] Audio stream started');

      // Listen to audio stream
      _audioSubscription = recordStream.listen(
        (data) {
          if (data.isNotEmpty) {
            print('[AudioCaptureService] Audio frame received: ${data.length} bytes');
            onAudioData(data);
          }
        },
        onError: (error) {
          print('[AudioCaptureService] Stream error: $error');
        },
        onDone: () {
          print('[AudioCaptureService] Stream done');
        },
      );
    } catch (e) {
      print('[AudioCaptureService] Error starting capture: $e');
      rethrow;
    }
  }

  Future<void> stopCapturing() async {
    try {
      print('[AudioCaptureService] Stopping audio capture...');
      _audioSubscription?.cancel();
      
      final isRecording = await _recorder.isRecording();
      if (isRecording) {
        final path = await _recorder.stop();
        print('[AudioCaptureService] Recording stopped at: $path');
      }
    } catch (e) {
      print('[AudioCaptureService] Error stopping capture: $e');
    }
  }

  void dispose() {
    _audioSubscription?.cancel();
    _recorder.dispose();
  }
}
