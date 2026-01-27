# Best Strategy to Avoid Duplicates Between System Audio and Mic

## Current Implementation
- **Time-based suppression**: Suppress mic audio for 1.5s after system final transcript
- **Bidirectional**: Also suppress system audio for 1.5s after mic final transcript

## Recommended Hybrid Approach (Best Practice)

### 1. **Time-Based Suppression at Audio Level** ✅ (Current - Keep)
**Why**: Prevents echo from being sent to Deepgram in the first place
- Suppress mic audio for 1.5-2 seconds after system final transcript
- Suppress system audio for 1.5-2 seconds after mic final transcript
- **Pros**: Prevents processing overhead, most effective for immediate echo
- **Cons**: Fixed window may miss delayed echo or similar content

### 2. **Text Similarity Matching at Transcript Level** (Add as Backup)
**Why**: Catches duplicates that slip through time-based suppression
- When a final transcript arrives, check against recent transcripts from other source
- Use similarity matching (word overlap, substring matching)
- If similarity > 70%, prefer system source over mic
- **Pros**: Catches delayed echo, handles similar content
- **Cons**: Requires processing, may have false positives

### 3. **Source Priority Strategy** (Add)
**Why**: System audio is typically the original source
- When duplicates detected: Always prefer system over mic
- System audio = original (from apps, video calls, etc.)
- Mic audio = echo/feedback (picked up by microphone)
- **Pros**: Simple rule, aligns with typical use case
- **Cons**: May not work if user is speaking (mic is original)

### 4. **Confidence-Based Filtering** (Optional Enhancement)
**Why**: Higher confidence usually means better transcription
- When duplicates detected, compare confidence scores
- Prefer transcript with higher confidence
- **Pros**: More accurate transcript wins
- **Cons**: Requires confidence scores from Deepgram

## Recommended Implementation Priority

### Phase 1: Optimize Current Approach ✅
1. **Adjust suppression window** based on testing:
   - 1.5s may be too short for some setups
   - Consider 2-3 seconds for better coverage
   - Make it configurable

2. **Add text similarity as backup**:
   - Keep time-based suppression (primary defense)
   - Add similarity check for final transcripts (secondary defense)
   - Only check last 5-10 bubbles to avoid performance issues

### Phase 2: Enhanced Detection (If Needed)
1. **Confidence-based filtering**: Use Deepgram confidence scores
2. **Adaptive window**: Adjust suppression window based on room acoustics
3. **Audio correlation**: Compare audio waveforms (advanced, requires more processing)

## Code Structure Recommendation

```dart
// Primary: Time-based suppression (at audio capture)
if (timeSinceSystemFinal < suppressionWindow) {
  return; // Don't send to Deepgram
}

// Secondary: Text similarity check (at transcript level)
if (isSimilarToRecentTranscript(otherSource)) {
  if (source == TranscriptSource.mic) {
    return; // Ignore mic duplicate
  }
  // Replace mic with system version
}
```

## Best Practice Summary

**The best approach is a two-layer defense:**

1. **Layer 1 (Audio Level)**: Time-based suppression
   - Prevents 90% of duplicates at the source
   - Low overhead, immediate effect
   - Current implementation ✅

2. **Layer 2 (Transcript Level)**: Text similarity matching
   - Catches remaining 10% that slip through
   - Handles edge cases and delayed echo
   - Should be added as backup ✅

**Why this works:**
- Time-based catches immediate echo (most common case)
- Similarity matching catches delayed echo or similar content
- Source priority ensures correct transcript is kept
- Minimal performance impact (similarity check only on final transcripts)

## Implementation Notes

- Keep suppression windows short (1.5-2s) to avoid blocking legitimate audio
- Similarity threshold: 70% word overlap is a good balance
- Only check recent bubbles (last 10) for performance
- Log when duplicates are detected for debugging
- Make suppression window configurable for different environments
