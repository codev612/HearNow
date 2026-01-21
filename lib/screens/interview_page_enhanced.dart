import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../config/app_config.dart';
import '../providers/speech_to_text_provider.dart';
import '../providers/interview_provider.dart';
import '../models/interview_session.dart';
import '../models/transcript_bubble.dart';
import '../services/interview_question_service.dart';
import '../services/ai_service.dart';

class InterviewPageEnhanced extends StatefulWidget {
  const InterviewPageEnhanced({super.key});

  @override
  State<InterviewPageEnhanced> createState() => _InterviewPageEnhancedState();
}

class _InterviewPageEnhancedState extends State<InterviewPageEnhanced> {
  final ScrollController _transcriptScrollController = ScrollController();
  final TextEditingController _askAiController = TextEditingController();
  final TextEditingController _aiResponseController = TextEditingController();
  final TextEditingController _sessionTitleController = TextEditingController();
  int _lastBubbleCount = 0;
  String _lastTailSignature = '';
  String _suggestedQuestions = '';
  bool _showQuestionSuggestions = false;
  bool _showSummary = false;
  bool _showInsights = false;
  SpeechToTextProvider? _speechProvider;
  InterviewProvider? _interviewProvider;
  Timer? _recordingTimer;
  DateTime? _recordingStartedAt;
  bool _showMarkers = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speechProvider = context.read<SpeechToTextProvider>();
      _interviewProvider = context.read<InterviewProvider>();
      
      _speechProvider!.initialize(
        wsUrl: AppConfig.serverWebSocketUrl,
        httpBaseUrl: AppConfig.serverHttpBaseUrl,
      );

      // Create new session if none exists
      if (_interviewProvider!.currentSession == null) {
        _interviewProvider!.createNewSession();
      }

      // Sync bubbles to interview session
      _speechProvider!.addListener(_syncBubblesToSession);
    });
  }

  void _syncBubblesToSession() {
    if (_interviewProvider?.currentSession != null && _speechProvider != null) {
      _interviewProvider!.updateCurrentSessionBubbles(_speechProvider!.bubbles);
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _transcriptScrollController.dispose();
    _askAiController.dispose();
    _aiResponseController.dispose();
    _sessionTitleController.dispose();
    _speechProvider?.removeListener(_syncBubblesToSession);
    super.dispose();
  }

  void _ensureRecordingClock(SpeechToTextProvider speechProvider) {
    if (speechProvider.isRecording) {
      _recordingStartedAt ??= DateTime.now();
      _recordingTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    } else {
      _recordingStartedAt = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;
    }
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    if (hh > 0) {
      return '${hh.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  String _formatWallTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _copyLastOtherSide() async {
    final bubbles = context.read<SpeechToTextProvider>().bubbles;
    for (var i = bubbles.length - 1; i >= 0; i--) {
      final b = bubbles[i];
      if (b.isDraft) continue;
      if (b.source != TranscriptSource.system) continue;
      final t = b.text.trim();
      if (t.isEmpty) continue;
      await Clipboard.setData(ClipboardData(text: t));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied last other-side turn')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No other-side turn found yet')),
    );
  }

  TranscriptBubble? _lastFinalBubble({TranscriptSource? source}) {
    final bubbles = context.read<SpeechToTextProvider>().bubbles;
    for (var i = bubbles.length - 1; i >= 0; i--) {
      final b = bubbles[i];
      if (b.isDraft) continue;
      if (source != null && b.source != source) continue;
      final t = b.text.trim();
      if (t.isEmpty) continue;
      return b;
    }
    return null;
  }

  Future<void> _markMoment() async {
    final interviewProvider = context.read<InterviewProvider>();
    final now = DateTime.now();
    final elapsed = _recordingStartedAt == null ? null : now.difference(_recordingStartedAt!);

    // Prefer the other-side (system) last turn, otherwise fall back to last mic.
    final last = _lastFinalBubble(source: TranscriptSource.system) ??
        _lastFinalBubble(source: TranscriptSource.mic) ??
        _lastFinalBubble();

    final defaultText = (last?.text.trim() ?? '');
    final source = (last?.source == null) ? '' : last!.source.toString().split('.').last;

    final note = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: '');
        return AlertDialog(
          title: const Text('Mark moment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (defaultText.isNotEmpty) ...[
                Text(
                  defaultText.length > 180 ? '${defaultText.substring(0, 180)}…' : defaultText,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Quick note (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save marker'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (note == null) return;

    interviewProvider.addMarker({
      'id': now.millisecondsSinceEpoch.toString(),
      'at': elapsed == null ? _formatWallTime(now) : _formatDuration(elapsed),
      'wallTime': now.toIso8601String(),
      'source': source,
      'text': defaultText,
      'label': note,
    });

    setState(() => _showMarkers = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked moment')),
    );
  }

  Future<void> _showTextDialog({
    required String title,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title is empty')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(t),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: t));
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMarkersDialog(InterviewProvider interviewProvider) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Markers (${interviewProvider.markers.length})'),
        content: SizedBox(
          width: 720,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: interviewProvider.markers.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final m = interviewProvider.markers[index];
                final at = (m['at']?.toString() ?? '').trim();
                final label = (m['label']?.toString() ?? '').trim();
                final text = (m['text']?.toString() ?? '').trim();
                final source = (m['source']?.toString() ?? '').trim();
                final display = [
                  if (at.isNotEmpty) at,
                  if (source.isNotEmpty) '[$source]',
                  if (label.isNotEmpty) label,
                ].join(' ');
                return ListTile(
                  title: Text(display.isEmpty ? 'Marker' : display),
                  subtitle: text.isEmpty ? null : Text(text),
                  onTap: () async {
                    final clip = [
                      if (at.isNotEmpty) at,
                      if (source.isNotEmpty) '[$source]',
                      if (label.isNotEmpty) label,
                      if (text.isNotEmpty) '\n$text',
                    ].join(' ');
                    await Clipboard.setData(ClipboardData(text: clip.trim()));
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Marker copied')),
                    );
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _maybeAutoScroll(SpeechToTextProvider provider) {
    final bubbleCount = provider.bubbles.length;
    final tail = provider.bubbles.isNotEmpty ? provider.bubbles.last : null;
    final tailSignature = tail == null
        ? ''
        : '${tail.source}:${tail.isDraft}:${tail.text.length}:${tail.timestamp.millisecondsSinceEpoch}';

    final changed = bubbleCount != _lastBubbleCount || tailSignature != _lastTailSignature;
    _lastBubbleCount = bubbleCount;
    _lastTailSignature = tailSignature;

    if (!changed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_transcriptScrollController.hasClients) return;

      final position = _transcriptScrollController.position;
      final target = position.maxScrollExtent;
      if ((target - position.pixels).abs() < 4) return;
      _transcriptScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildBubble({required TranscriptSource source, required String text}) {
    final isMe = source == TranscriptSource.mic;
    final backgroundColor = isMe ? Colors.blue.shade600 : Colors.grey.shade300;
    final textColor = isMe ? Colors.white : Colors.black87;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: textColor,
              fontStyle: FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuestionTemplates() async {
    final category = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Question Templates'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: InterviewQuestionService.getQuestionsByCategoryMap().entries.map((entry) {
              return ListTile(
                title: Text(entry.key),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.pop(context, entry.key),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (category != null && mounted) {
      final questions = InterviewQuestionService.getQuestionsByCategory(category);
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$category Questions'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: questions.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(questions[index]),
                  onTap: () => Navigator.pop(context, questions[index]),
                );
              },
            ),
          ),
        ),
      );

      if (selected != null && mounted) {
        _askAiController.text = selected;
      }
    }
  }

  Future<void> _generateSuggestedQuestions() async {
    final interviewProvider = context.read<InterviewProvider>();
    final questions = await interviewProvider.generateQuestions();
    if (questions.isNotEmpty && mounted) {
      setState(() {
        _suggestedQuestions = questions;
        _showQuestionSuggestions = true;
      });
    }
  }

  Future<void> _saveSession() async {
    final interviewProvider = context.read<InterviewProvider>();
    final title = _sessionTitleController.text.trim();
    
    await interviewProvider.saveCurrentSession(
      title: title.isNotEmpty ? title : null,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session saved')),
      );
    }
  }

  Future<void> _exportSession() async {
    final interviewProvider = context.read<InterviewProvider>();
    if (interviewProvider.currentSession == null) return;

    try {
      final text = await interviewProvider.exportSessionAsText(
        interviewProvider.currentSession!.id,
      );
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session exported to clipboard')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Widget _buildTranscript(SpeechToTextProvider speechProvider) {
    final bubbles = speechProvider.bubbles;
    final hasAny = bubbles.isNotEmpty;

    if (!hasAny) {
      return const Center(
        child: Text(
          'Tap the microphone button to start recording',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _transcriptScrollController,
      itemCount: bubbles.length,
      itemBuilder: (context, index) {
        final b = bubbles[index];
        return _buildBubble(source: b.source, text: b.text);
      },
    );
  }

  Widget _buildConversationPanel(
    SpeechToTextProvider speechProvider,
    InterviewProvider interviewProvider,
  ) {
    _ensureRecordingClock(speechProvider);
    final isRec = speechProvider.isRecording;
    final elapsed = _recordingStartedAt == null ? null : DateTime.now().difference(_recordingStartedAt!);
    const dockButtonSize = 48.0;
    final dockButtonStyle = IconButton.styleFrom(
      minimumSize: const Size(dockButtonSize, dockButtonSize),
      maximumSize: const Size(dockButtonSize, dockButtonSize),
      padding: EdgeInsets.zero,
      iconSize: 22,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Small top status row (kept minimal; primary controls are docked at bottom)
        SizedBox(
          height: dockButtonSize,
          child: Row(
            children: [
              if (isRec) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text('REC', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(
                  elapsed == null ? '' : _formatDuration(elapsed),
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ] else
                const Text('Ready', style: TextStyle(color: Colors.black54)),
              const Spacer(),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Transcript display
        Expanded(
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 92), // leave space for dock
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _buildTranscript(speechProvider),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          IconButton.filled(
                            onPressed: isRec ? speechProvider.stopRecording : speechProvider.startRecording,
                            tooltip: isRec ? 'Stop (Ctrl+R)' : 'Record (Ctrl+R)',
                            icon: Icon(isRec ? Icons.stop : Icons.mic),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(dockButtonSize, dockButtonSize),
                              maximumSize: const Size(dockButtonSize, dockButtonSize),
                              padding: EdgeInsets.zero,
                              iconSize: 22,
                              backgroundColor: isRec ? Colors.red : Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: _markMoment,
                            tooltip: 'Mark moment (Ctrl+M)',
                            icon: const Icon(Icons.bookmark_add_outlined),
                            style: dockButtonStyle,
                          ),
                          IconButton.outlined(
                            onPressed: isRec ? null : speechProvider.clearTranscript,
                            tooltip: 'Clear transcript',
                            icon: const Icon(Icons.clear),
                            style: dockButtonStyle,
                          ),
                          IconButton.outlined(
                            onPressed: interviewProvider.isLoading ? null : _saveSession,
                            tooltip: 'Save session (Ctrl+S)',
                            icon: const Icon(Icons.save),
                            style: dockButtonStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiPanel({
    required SpeechToTextProvider speechProvider,
    required InterviewProvider interviewProvider,
    required InterviewSession? session,
    required bool twoColumn,
  }) {
    const dockButtonSize = 48.0;
    final dockButtonStyle = IconButton.styleFrom(
      minimumSize: const Size(dockButtonSize, dockButtonSize),
      maximumSize: const Size(dockButtonSize, dockButtonSize),
      padding: EdgeInsets.zero,
      iconSize: 22,
    );
    if (!twoColumn) {
      // In single-column mode, make the AI panel scrollable.
      return LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: interviewProvider.isGeneratingSummary
                        ? null
                        : () async {
                            await interviewProvider.generateSummary();
                            final s = interviewProvider.currentSession?.summary ?? '';
                            await _showTextDialog(title: 'Summary', text: s);
                          },
                    icon: interviewProvider.isGeneratingSummary
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.summarize),
                    label: const Text('Summary'),
                  ),
                  OutlinedButton.icon(
                    onPressed: interviewProvider.isGeneratingInsights
                        ? null
                        : () async {
                            await interviewProvider.generateInsights();
                            final s = interviewProvider.currentSession?.insights ?? '';
                            await _showTextDialog(title: 'Insights', text: s);
                          },
                    icon: interviewProvider.isGeneratingInsights
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.insights),
                    label: const Text('Insights'),
                  ),
                  OutlinedButton.icon(
                    onPressed: interviewProvider.isGeneratingQuestions
                        ? null
                        : () async {
                            await _generateSuggestedQuestions();
                            await _showTextDialog(title: 'Suggested Questions', text: _suggestedQuestions);
                          },
                    icon: interviewProvider.isGeneratingQuestions
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.help_outline),
                    label: const Text('Questions'),
                  ),
                  OutlinedButton.icon(
                    onPressed: interviewProvider.markers.isEmpty ? null : () => _showMarkersDialog(interviewProvider),
                    icon: const Icon(Icons.bookmarks_outlined),
                    label: const Text('Markers'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Ask AI
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _askAiController,
                      enabled: !speechProvider.isAiLoading,
                      decoration: const InputDecoration(
                        labelText: 'Ask AI (optional)',
                        hintText: 'e.g., \"What should I ask next?\"',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (value) => speechProvider.askAi(question: value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.quiz),
                    tooltip: 'Question Templates',
                    onPressed: _showQuestionTemplates,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: speechProvider.isAiLoading
                        ? null
                        : () => speechProvider.askAi(question: _askAiController.text),
                    icon: speechProvider.isAiLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(speechProvider.isAiLoading ? 'Asking…' : 'Ask (Ctrl+Enter)'),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 240,
                child: TextField(
                  controller: _aiResponseController,
                  readOnly: true,
                  minLines: null,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    labelText: 'AI Response',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    // In two-column mode, keep the response area height stable (matching transcript).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Prompt input + Ask button ABOVE the AI response field
        SizedBox(
          height: dockButtonSize,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _askAiController,
                  enabled: !speechProvider.isAiLoading,
                  decoration: const InputDecoration(
                    hintText: 'Ask AI… (Ctrl+Enter)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) => speechProvider.askAi(question: value),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: 'Templates',
                onPressed: _showQuestionTemplates,
                icon: const Icon(Icons.quiz),
                style: dockButtonStyle,
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Ask (Ctrl+Enter)',
                onPressed: speechProvider.isAiLoading
                    ? null
                    : () => speechProvider.askAi(question: _askAiController.text),
                icon: speechProvider.isAiLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                style: IconButton.styleFrom(
                  minimumSize: const Size(dockButtonSize, dockButtonSize),
                  maximumSize: const Size(dockButtonSize, dockButtonSize),
                  padding: EdgeInsets.zero,
                  iconSize: 22,
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 92), // leave space for dock
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _aiResponseController,
                  readOnly: true,
                  minLines: null,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          IconButton.outlined(
                            tooltip: 'Summary',
                            onPressed: interviewProvider.isGeneratingSummary
                                ? null
                                : () async {
                                    await interviewProvider.generateSummary();
                                    final s = interviewProvider.currentSession?.summary ?? '';
                                    await _showTextDialog(title: 'Summary', text: s);
                                  },
                            icon: interviewProvider.isGeneratingSummary
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.summarize),
                            style: dockButtonStyle,
                          ),
                          IconButton.outlined(
                            tooltip: 'Insights',
                            onPressed: interviewProvider.isGeneratingInsights
                                ? null
                                : () async {
                                    await interviewProvider.generateInsights();
                                    final s = interviewProvider.currentSession?.insights ?? '';
                                    await _showTextDialog(title: 'Insights', text: s);
                                  },
                            icon: interviewProvider.isGeneratingInsights
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.insights),
                            style: dockButtonStyle,
                          ),
                          IconButton.outlined(
                            tooltip: 'Questions',
                            onPressed: interviewProvider.isGeneratingQuestions
                                ? null
                                : () async {
                                    await _generateSuggestedQuestions();
                                    await _showTextDialog(title: 'Suggested Questions', text: _suggestedQuestions);
                                  },
                            icon: interviewProvider.isGeneratingQuestions
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.help_outline),
                            style: dockButtonStyle,
                          ),
                          IconButton.outlined(
                            tooltip: 'Markers',
                            onPressed: interviewProvider.markers.isEmpty ? null : () => _showMarkersDialog(interviewProvider),
                            icon: const Icon(Icons.bookmarks_outlined),
                            style: dockButtonStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpeechToTextProvider, InterviewProvider>(
      builder: (context, speechProvider, interviewProvider, child) {
        _maybeAutoScroll(speechProvider);

        final aiText = speechProvider.aiErrorMessage.isNotEmpty
            ? 'Error: ${speechProvider.aiErrorMessage}'
            : speechProvider.aiResponse;
        if (_aiResponseController.text != aiText) {
          _aiResponseController.text = aiText;
          _aiResponseController.selection = TextSelection.collapsed(
            offset: _aiResponseController.text.length,
          );
        }

        final session = interviewProvider.currentSession;
        if (_sessionTitleController.text.isEmpty && session != null) {
          _sessionTitleController.text = session.title;
        }

        final shortcuts = <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.keyR, control: true): const _ToggleRecordIntent(),
          const SingleActivator(LogicalKeyboardKey.enter, control: true): const _AskAiIntent(),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): const _SaveSessionIntent(),
          const SingleActivator(LogicalKeyboardKey.keyE, control: true): const _ExportIntent(),
          const SingleActivator(LogicalKeyboardKey.keyM, control: true): const _MarkIntent(),
        };

        return Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: <Type, Action<Intent>>{
              _ToggleRecordIntent: CallbackAction<_ToggleRecordIntent>(
                onInvoke: (_) {
                  if (speechProvider.isRecording) {
                    speechProvider.stopRecording();
                  } else {
                    speechProvider.startRecording();
                  }
                  return null;
                },
              ),
              _AskAiIntent: CallbackAction<_AskAiIntent>(
                onInvoke: (_) {
                  speechProvider.askAi(question: _askAiController.text);
                  return null;
                },
              ),
              _SaveSessionIntent: CallbackAction<_SaveSessionIntent>(
                onInvoke: (_) {
                  if (!interviewProvider.isLoading) _saveSession();
                  return null;
                },
              ),
              _ExportIntent: CallbackAction<_ExportIntent>(
                onInvoke: (_) {
                  if (session != null) _exportSession();
                  return null;
                },
              ),
              _MarkIntent: CallbackAction<_MarkIntent>(
                onInvoke: (_) {
                  _markMoment();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Session title and actions (rare actions in menu; core actions are docked)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sessionTitleController,
                            decoration: const InputDecoration(
                              labelText: 'Session Title',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.file_download),
                          tooltip: 'Export (Ctrl+E)',
                          onPressed: session == null ? null : _exportSession,
                        ),
                        PopupMenuButton(
                          icon: const Icon(Icons.more_vert),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'sessions',
                              child: Row(
                                children: [
                                  Icon(Icons.folder, size: 20),
                                  SizedBox(width: 8),
                                  Text('Manage Sessions'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'new',
                              child: Row(
                                children: [
                                  Icon(Icons.add, size: 20),
                                  SizedBox(width: 8),
                                  Text('New Session'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'sessions') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SessionsListPage(),
                                ),
                              );
                            } else if (value == 'new') {
                              interviewProvider.createNewSession();
                              _sessionTitleController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Error message
                    if (speechProvider.errorMessage.isNotEmpty ||
                        interviewProvider.errorMessage.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                speechProvider.errorMessage.isNotEmpty
                                    ? speechProvider.errorMessage
                                    : interviewProvider.errorMessage,
                                style: TextStyle(color: Colors.red.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final twoColumn = constraints.maxWidth >= 900;

                          if (!twoColumn) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildConversationPanel(speechProvider, interviewProvider),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  flex: 2,
                                  child: _buildAiPanel(
                                    speechProvider: speechProvider,
                                    interviewProvider: interviewProvider,
                                    session: session,
                                    twoColumn: false,
                                  ),
                                ),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _buildConversationPanel(speechProvider, interviewProvider)),
                              const SizedBox(width: 16),
                              VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildAiPanel(
                                  speechProvider: speechProvider,
                                  interviewProvider: interviewProvider,
                                  session: session,
                                  twoColumn: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToggleRecordIntent extends Intent {
  const _ToggleRecordIntent();
}

class _AskAiIntent extends Intent {
  const _AskAiIntent();
}

class _SaveSessionIntent extends Intent {
  const _SaveSessionIntent();
}

class _ExportIntent extends Intent {
  const _ExportIntent();
}

class _MarkIntent extends Intent {
  const _MarkIntent();
}

// Sessions List Page
class SessionsListPage extends StatefulWidget {
  const SessionsListPage({super.key});

  @override
  State<SessionsListPage> createState() => _SessionsListPageState();
}

class _SessionsListPageState extends State<SessionsListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InterviewProvider>().loadSessions();
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interview Sessions'),
      ),
      body: Consumer<InterviewProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.sessions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.sessions.isEmpty) {
            return const Center(
              child: Text('No saved sessions'),
            );
          }

          return ListView.builder(
            itemCount: provider.sessions.length,
            itemBuilder: (context, index) {
              final session = provider.sessions[index];
              return ListTile(
                title: Text(session.title),
                subtitle: Text(
                  '${session.createdAt.toLocal().toString().substring(0, 16)} • ${_formatDuration(session.duration)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Export',
                      onPressed: () async {
                        try {
                          final text = await provider.exportSessionAsText(session.id);
                          await Clipboard.setData(ClipboardData(text: text));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Exported to clipboard')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Export failed: $e')),
                            );
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'Delete',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Session?'),
                            content: Text('Delete "${session.title}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          await provider.deleteSession(session.id);
                        }
                      },
                    ),
                  ],
                ),
                onTap: () async {
                  await provider.loadSession(session.id);
                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
