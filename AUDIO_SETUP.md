# Audio Capture Implementation - Setup Guide

## What's Been Implemented

### 1. **Microphone Audio Capture** ✅
- Real-time audio recording from the device microphone
- PCM 16-bit encoding at 16kHz sample rate
- Cross-platform support via the `record` package
- Streams audio chunks continuously to the backend

**Files:**
- [lib/services/audio_capture_service.dart](lib/services/audio_capture_service.dart) - Audio capture wrapper
- [lib/providers/speech_to_text_provider.dart](lib/providers/speech_to_text_provider.dart) - Integration with provider

### 2. **System Audio Capture** (Windows) 🔧
- Platform channel setup for Windows audio loopback
- Captures system sound (Stereo Mix / Loopback Recording)
- Audio mixing functionality to combine mic + system audio

**Files:**
- [lib/services/windows_audio_service.dart](lib/services/windows_audio_service.dart) - Windows audio API interface
- [windows/runner/audio_capture.h](windows/runner/audio_capture.h) - C++ header
- [windows/runner/audio_capture.cpp](windows/runner/audio_capture.cpp) - C++ implementation
- [windows/runner/flutter_window.cpp](windows/runner/flutter_window.cpp) - Platform channel handler

### 3. **Audio Mixing**
- `WindowsAudioService.mixAudio()` - Combines microphone and system audio
- Simple averaging algorithm to prevent clipping
- Maintains audio quality

## How It Works

### Microphone Capture Flow
1. User clicks "Record" button
2. App requests microphone permission
3. `AudioCaptureService` starts recording with PCM configuration
4. Audio frames stream from the microphone
5. Each frame is sent to the WebSocket backend
6. Backend forwards to Deepgram for transcription

### System Audio Capture Flow (Windows)
1. Platform channel calls Windows audio APIs via C++
2. Captures from Stereo Mix / Loopback Recording device
3. Returns audio frames to Dart
4. Mixes with microphone audio if desired

## Configuration

### Audio Format
- **Codec**: PCM 16-bit
- **Sample Rate**: 16000 Hz
- **Channels**: 1 (Mono)
- **Bit Rate**: 128 kbps

### Permissions Required
- **Android**: RECORD_AUDIO, INTERNET
- **iOS**: Microphone usage description
- **Windows**: No special permissions needed
- **macOS**: Microphone permission required
- **Linux**: ALSA permissions

## Next Steps to Enable System Audio

To fully implement system audio capture, you need to:

### Windows Implementation
The C++ code in `audio_capture.cpp` currently has stubs. To implement:

1. **Using WASAPI (Recommended)**:
```cpp
#include <audioclient.h>
#include <mmdeviceapi.h>

// 1. Get default loopback device
// 2. Create audio client
// 3. Initialize for capture
// 4. Start capture
// 5. Return audio frames to Dart
```

2. **Or use direct audio APIs**:
- Detect Stereo Mix device
- Capture from default loopback

### Android Implementation
```dart
// Use android_alarm_manager or background audio capture
// Capture from AudioRecord with loopback
```

### macOS Implementation
```swift
// Use AVAudioEngine with loopback recording
// Or use CoreAudio APIs
```

### iOS Implementation
```swift
// Limited options due to iOS restrictions
// Can use ReplayKit for screen audio
```

## Testing

### Current Status
✅ Microphone capture: **WORKING**
🔧 System audio capture: **SETUP (needs implementation)**
✅ WebSocket transmission: **WORKING**
✅ Backend processing: **WORKING**

### To Test Microphone
1. Run the app
2. Click Record
3. Speak into your microphone
4. Check console logs for: `[SpeechToTextProvider] Audio frame #X: XXXX bytes`
5. Verify transcriptions in the app UI

### To Test System Audio (when implemented)
1. Ensure "Stereo Mix" is enabled in Windows Sound Settings
2. Run the app
3. Play audio from speaker/browser
4. Click Record
5. Check if system audio is captured

## Audio Mixing Example

```dart
// Example: Mix microphone (micAudio) with system audio (systemAudio)
List<int> mixedAudio = WindowsAudioService.mixAudio(micAudio, systemAudio);
```

The mixing algorithm:
1. Reads 16-bit samples from both streams
2. Averages the samples: `(mic + system) / 2`
3. Clamps to prevent overflow: `[-32768, 32767]`
4. Returns combined audio

## Performance Considerations

- **CPU Usage**: Real-time audio capture uses moderate CPU
- **Memory**: Streams chunks (no buffering entire audio)
- **Latency**: ~100-200ms due to chunking
- **Network**: Audio sent continuously, no compression yet

## Future Enhancements

1. **Noise Suppression**: Add audio preprocessing
2. **Echo Cancellation**: Remove system audio echo
3. **Compression**: Reduce bandwidth with audio codecs
4. **Multi-device**: Support multiple audio inputs
5. **Audio Visualization**: Show audio levels in UI

## Troubleshooting

### No audio captured
- Check microphone permissions
- Verify microphone is enabled in OS
- Check Windows audio recording device is "Microphone" not "Stereo Mix"

### System audio not working
- Enable Stereo Mix in Windows Sound Settings
- Run app with administrator privileges
- Check Windows audio driver supports loopback

### Audio quality issues
- Increase sample rate in RecordConfig
- Reduce chunk size for lower latency
- Check network bandwidth for streaming

## References

- [Flutter Record Package](https://pub.dev/packages/record)
- [Windows WASAPI Documentation](https://docs.microsoft.com/en-us/windows/win32/coreaudio/wasapi)
- [Deepgram Audio Requirements](https://developers.deepgram.com/reference/pre-recorded)
