# Resource Optimization Guide for FinalRound

## Overview
This guide outlines best practices and optimizations for managing resources efficiently in the FinalRound application.

## 1. Memory Management

### ✅ Current Good Practices
- **Dispose Pattern**: Providers properly dispose timers, subscriptions, and services
- **Stream Cleanup**: WebSocket subscriptions are cancelled in dispose methods
- **Service Lifecycle**: Audio capture services are disposed when not in use

### 🔧 Optimization Opportunities

#### 1.1 Limit Transcript Bubble History
**Current**: All bubbles are kept in memory indefinitely
**Optimization**: Limit bubble history to last N bubbles (e.g., 1000) for active sessions
```dart
// In SpeechToTextProvider
static const int _maxBubblesInMemory = 1000;

void _addBubble(TranscriptBubble bubble) {
  _bubbles.add(bubble);
  if (_bubbles.length > _maxBubblesInMemory) {
    _bubbles.removeAt(0); // Remove oldest
  }
}
```

#### 1.2 Implement ListView Virtualization
**Current**: All sessions loaded at once
**Optimization**: Use pagination (already implemented ✅) and lazy loading

#### 1.3 Cache Management
**Current**: Mode configs and question templates cached in SharedPreferences
**Optimization**: 
- Implement cache expiration (e.g., 24 hours)
- Clear old cache entries periodically
- Limit cache size

## 2. Network Optimization

### ✅ Current Good Practices
- **WebSocket Reuse**: Single WebSocket connection for transcription
- **Debounced Search**: 500ms debounce for search queries
- **Pagination**: Sessions loaded in pages of 20

### 🔧 Optimization Opportunities

#### 2.1 WebSocket Connection Pooling
**Current**: New connections created per request
**Optimization**: Reuse WebSocket connections with connection pooling
```dart
// Implement connection reuse
class WebSocketPool {
  final Map<String, WebSocketChannel> _connections = {};
  
  WebSocketChannel getConnection(String url) {
    if (_connections.containsKey(url) && _connections[url]!.readyState == WebSocket.OPEN) {
      return _connections[url]!;
    }
    // Create new connection
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _connections[url] = channel;
    return channel;
  }
}
```

#### 2.2 Request Batching
**Current**: Individual API calls for each operation
**Optimization**: Batch multiple operations (e.g., save multiple templates at once)

#### 2.3 Compression
**Current**: Audio sent as base64
**Optimization**: 
- Use binary WebSocket frames instead of base64
- Compress large payloads (e.g., session exports)

#### 2.4 Reduce Audio Frame Size
**Current**: Audio frames sent frequently
**Optimization**: 
- Increase frame size slightly (reduce frequency)
- Batch multiple frames before sending

## 3. CPU Optimization

### ✅ Current Good Practices
- **Timer Cleanup**: All timers cancelled in dispose
- **Background Processing**: Heavy operations done in microtasks

### 🔧 Optimization Opportunities

#### 3.1 Reduce Polling Frequency
**Current**: System audio polled every 50ms
**Optimization**: 
- Increase to 100ms when idle
- Adaptive polling (faster when active, slower when idle)

#### 3.2 Debounce Expensive Operations
**Current**: Auto-save has 2-second debounce ✅
**Optimization**: 
- Debounce bubble updates (batch multiple updates)
- Debounce UI rebuilds

#### 3.3 Use Isolates for Heavy Processing
**Current**: All processing on main thread
**Optimization**: 
- Move transcript processing to isolates
- Move similarity calculations to isolates

#### 3.4 Optimize Text Similarity Calculation
**Current**: Full text comparison
**Optimization**: 
- Use hash-based comparison first
- Only do full comparison if hash matches
- Limit comparison window (last 10 bubbles)

## 4. Battery Optimization

### ✅ Current Good Practices
- **Conditional Audio Capture**: Mic only captured when enabled
- **Service Cleanup**: Services stopped when not recording

### 🔧 Optimization Opportunities

#### 4.1 Adaptive Audio Quality
**Current**: Fixed audio quality
**Optimization**: 
- Lower quality when battery is low
- Reduce sample rate when idle

#### 4.2 Background Processing Limits
**Current**: Continuous processing
**Optimization**: 
- Pause processing when app is in background
- Resume when app comes to foreground

#### 4.3 Reduce Timer Frequency
**Current**: Recording timer updates every second
**Optimization**: 
- Update every 5 seconds when not actively recording
- Only update UI when visible

## 5. Storage Optimization

### ✅ Current Good Practices
- **SharedPreferences**: Used for small data
- **MongoDB**: Used for large data (sessions)

### 🔧 Optimization Opportunities

#### 5.1 Session Data Cleanup
**Current**: All sessions kept indefinitely
**Optimization**: 
- Auto-delete old sessions (e.g., >90 days)
- Compress old session data
- Archive inactive sessions

#### 5.2 Cache Size Limits
**Current**: Unlimited cache growth
**Optimization**: 
- Limit SharedPreferences cache size
- Implement LRU eviction for caches

#### 5.3 Database Indexing
**Current**: Basic queries
**Optimization**: 
- Add indexes on frequently queried fields (userId, createdAt, modeKey)
- Use compound indexes for common queries

## 6. UI/UX Optimization

### ✅ Current Good Practices
- **Lazy Loading**: ListView.builder for sessions
- **Pagination**: Limits items per page

### 🔧 Optimization Opportunities

#### 6.1 Image/Icon Optimization
**Current**: Standard Material icons
**Optimization**: 
- Use vector icons (already using ✅)
- Cache rendered icons

#### 6.2 Reduce Rebuilds
**Current**: Some unnecessary rebuilds
**Optimization**: 
- Use `const` widgets where possible
- Use `Consumer` with specific providers
- Implement `shouldRebuild` for custom widgets

#### 6.3 List Performance
**Current**: Full list rendering
**Optimization**: 
- Use `ListView.builder` with `itemExtent` for fixed-height items
- Implement `AutomaticKeepAliveClientMixin` for complex items

## 7. Implementation Priority

### High Priority (Immediate Impact)
1. ✅ **Timer Cleanup** - Already implemented
2. ✅ **Stream Subscription Cleanup** - Already implemented  
3. 🔧 **Limit Bubble History** - Prevent memory growth
4. 🔧 **Reduce Polling Frequency** - Save CPU/battery
5. 🔧 **WebSocket Connection Reuse** - Reduce connection overhead

### Medium Priority (Performance Gains)
1. 🔧 **Batch API Requests** - Reduce network calls
2. 🔧 **Use Binary WebSocket** - Reduce bandwidth
3. 🔧 **Debounce Bubble Updates** - Reduce processing
4. 🔧 **Cache Expiration** - Prevent stale data

### Low Priority (Nice to Have)
1. 🔧 **Isolate Processing** - Better CPU utilization
2. 🔧 **Adaptive Quality** - Battery optimization
3. 🔧 **Session Archiving** - Storage optimization

## 8. Monitoring & Profiling

### Tools to Use
- **Flutter DevTools**: Memory, CPU, network profiling
- **Dart Observatory**: Performance analysis
- **Chrome DevTools**: WebSocket monitoring

### Key Metrics to Monitor
- Memory usage (especially during long sessions)
- CPU usage (during audio processing)
- Network bandwidth (WebSocket data transfer)
- Battery drain (during recording)
- Frame rate (UI responsiveness)

## 9. Code Examples

### Example 1: Limit Bubble History
```dart
class SpeechToTextProvider extends ChangeNotifier {
  static const int _maxBubblesInMemory = 1000;
  
  void _addBubble(TranscriptBubble bubble) {
    _bubbles.add(bubble);
    if (_bubbles.length > _maxBubblesInMemory) {
      // Keep only recent bubbles, oldest are already saved to session
      _bubbles.removeRange(0, _bubbles.length - _maxBubblesInMemory);
    }
    notifyListeners();
  }
}
```

### Example 2: Adaptive Polling
```dart
class SpeechToTextProvider extends ChangeNotifier {
  Timer? _systemAudioPollTimer;
  bool _isActive = false;
  
  void _startSystemAudioPoll() {
    final interval = _isActive 
        ? const Duration(milliseconds: 50)  // Fast when active
        : const Duration(milliseconds: 200); // Slower when idle
    
    _systemAudioPollTimer?.cancel();
    _systemAudioPollTimer = Timer.periodic(interval, (_) {
      // Poll system audio
    });
  }
}
```

### Example 3: Connection Pooling
```dart
class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  factory WebSocketManager() => _instance;
  WebSocketManager._internal();
  
  final Map<String, WebSocketChannel> _connections = {};
  
  WebSocketChannel getConnection(String url) {
    final existing = _connections[url];
    if (existing != null && existing.readyState == WebSocket.OPEN) {
      return existing;
    }
    
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _connections[url] = channel;
    return channel;
  }
  
  void closeConnection(String url) {
    _connections[url]?.sink.close();
    _connections.remove(url);
  }
}
```

## 10. Best Practices Summary

1. **Always Dispose**: Timers, subscriptions, controllers, services
2. **Limit Memory Growth**: Cap lists, implement pagination, clear old data
3. **Reuse Connections**: WebSocket, HTTP clients
4. **Debounce Operations**: Search, saves, updates
5. **Batch Operations**: Multiple API calls → single batch call
6. **Lazy Load**: Only load what's visible
7. **Cache Wisely**: Set expiration, limit size
8. **Profile Regularly**: Use DevTools to identify bottlenecks
9. **Monitor Metrics**: Track memory, CPU, network usage
10. **Test Edge Cases**: Long sessions, many sessions, low battery
