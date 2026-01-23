import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/meeting_provider.dart';
import '../providers/auth_provider.dart';
import '../models/meeting_session.dart';

class _HoverableListTile extends StatefulWidget {
  final MeetingSession session;
  final MeetingProvider provider;
  final String Function(DateTime) formatTime;
  final String Function(Duration) formatDuration;
  final VoidCallback? onLoadSession;
  final VoidCallback onStartMeeting;

  const _HoverableListTile({
    required this.session,
    required this.provider,
    required this.formatTime,
    required this.formatDuration,
    this.onLoadSession,
    required this.onStartMeeting,
  });

  @override
  State<_HoverableListTile> createState() => _HoverableListTileState();
}

class _HoverableListTileState extends State<_HoverableListTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: _isHovered
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          title: Text(widget.session.title),
          subtitle: Row(
            children: [
              Icon(
                Icons.access_time,
                size: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.formatTime(widget.session.createdAt)} • ${widget.formatDuration(widget.session.duration)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.session.bubbles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text('${widget.session.bubbles.length}'),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
          onTap: widget.provider.isLoading ? null : () {
            // Store callbacks and session ID immediately to avoid issues if widget is disposed
            final onLoadSession = widget.onLoadSession;
            final onStartMeeting = widget.onStartMeeting;
            final sessionId = widget.session.id;
            
            // Validate session ID before attempting to load
            if (sessionId.isEmpty) {
              print('[HomePage] Session ID is empty, cannot load session');
              // Still navigate to meeting page
              if (mounted && onLoadSession != null) {
                onLoadSession();
              } else if (mounted) {
                onStartMeeting();
              }
              return;
            }
            
            // Navigate immediately, then load session in background
            // This ensures navigation happens even if loadSession sets isLoading = true
            if (mounted) {
              if (onLoadSession != null) {
                onLoadSession();
              } else {
                onStartMeeting();
              }
            }
            
            // Load session asynchronously after navigation
            // Use a microtask to ensure navigation happens first
            Future.microtask(() async {
              try {
                await widget.provider.loadSession(sessionId).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    print('[HomePage] loadSession timed out after 10 seconds');
                  },
                );
              } catch (e) {
                print('[HomePage] Error loading session: $e');
                // Error is already handled by loadSession
              }
            });
          },
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onStartMeeting;
  final VoidCallback? onLoadSession;

  const HomePage({super.key, required this.onStartMeeting, this.onLoadSession});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final meetingProvider = context.read<MeetingProvider>();
      // Ensure auth token is set before loading sessions
      meetingProvider.updateAuthToken(authProvider.token);
      meetingProvider.loadSessions();
    });
  }

  String _formatDate(DateTime date) {
    // Convert to local time if it's in UTC
    final localDate = date.isUtc ? date.toLocal() : date;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(localDate.year, localDate.month, localDate.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      // Format: "January 15, 2024"
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    // Convert to local time if it's in UTC
    final localDate = date.isUtc ? date.toLocal() : date;
    final hour = localDate.hour == 0 ? 12 : (localDate.hour > 12 ? localDate.hour - 12 : localDate.hour);
    final minute = localDate.minute.toString().padLeft(2, '0');
    final period = localDate.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  Map<String, List<MeetingSession>> _groupSessionsByDate(List<MeetingSession> sessions) {
    final grouped = <String, List<MeetingSession>>{};
    for (final session in sessions) {
      final dateKey = _formatDate(session.createdAt);
      grouped.putIfAbsent(dateKey, () => []).add(session);
    }
    // Sort sessions within each date group (newest first)
    for (final sessions in grouped.values) {
      sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return grouped;
  }

  List<String> _getSortedDateKeys(Map<String, List<MeetingSession>> grouped) {
    final keys = grouped.keys.toList();
    // Sort dates: Today, Yesterday, then by date (newest first)
    keys.sort((a, b) {
      if (a == 'Today') return -1;
      if (b == 'Today') return 1;
      if (a == 'Yesterday') return -1;
      if (b == 'Yesterday') return 1;
      // For other dates, extract the date from the first session in each group
      final sessionsA = grouped[a]!;
      final sessionsB = grouped[b]!;
      if (sessionsA.isNotEmpty && sessionsB.isNotEmpty) {
        return sessionsB.first.createdAt.compareTo(sessionsA.first.createdAt);
      }
      return a.compareTo(b);
    });
    return keys;
  }

  Widget _buildSessionsList(Map<String, List<MeetingSession>> grouped, List<String> dateKeys, MeetingProvider provider) {
    return RefreshIndicator(
      onRefresh: () => provider.loadSessions(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: dateKeys.length,
        itemBuilder: (context, dateIndex) {
          final dateKey = dateKeys[dateIndex];
          final dateSessions = grouped[dateKey]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date header
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                child: Text(
                  dateKey,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              // Sessions for this date
              ...dateSessions.map((session) {
                return _HoverableListTile(
                  session: session,
                  provider: provider,
                  formatTime: _formatTime,
                  formatDuration: _formatDuration,
                  onLoadSession: widget.onLoadSession,
                  onStartMeeting: widget.onStartMeeting,
                );
              }),
              if (dateIndex < dateKeys.length - 1)
                const Divider(height: 1),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MeetingProvider>(
      builder: (context, provider, child) {
        final sessions = provider.sessions;
        final grouped = _groupSessionsByDate(sessions);
        final dateKeys = _getSortedDateKeys(grouped);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with title and start button
              Padding(
                padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HearNow',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Meeting assistant with separate mic + system transcripts.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 140,
                    child: FilledButton.icon(
                      onPressed: widget.onStartMeeting,
                      icon: const Icon(Icons.record_voice_over, size: 18),
                      label: const Text('Start Meeting', style: TextStyle(fontSize: 13)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Sessions list
            Expanded(
              child: provider.isLoading && sessions.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : provider.isLoading && sessions.isNotEmpty
                      ? Stack(
                          children: [
                            // Show existing sessions with reduced opacity
                            Opacity(
                              opacity: 0.5,
                              child: IgnorePointer(
                                child: _buildSessionsList(grouped, dateKeys, provider),
                              ),
                            ),
                            // Show loading overlay
                            const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ],
                        )
                      : grouped.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.event_note_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No saved meetings',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start a meeting to see it here',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                              ),
                            ],
                          ),
                        )
                      : _buildSessionsList(grouped, dateKeys, provider),
            ),
          ],
          ),
        );
      },
    );
  }
}
