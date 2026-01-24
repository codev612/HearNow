import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meeting_mode.dart';
import '../services/meeting_mode_service.dart';
import '../providers/auth_provider.dart';

class ManageModePage extends StatefulWidget {
  const ManageModePage({super.key});

  @override
  State<ManageModePage> createState() => _ManageModePageState();
}

class _ManageModePageState extends State<ManageModePage> {
  final MeetingModeService _modeService = MeetingModeService();
  Map<MeetingMode, MeetingModeConfig> _configs = {};
  bool _isLoading = true;
  MeetingMode? _selectedMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      _modeService.setAuthToken(authProvider.token);
      _loadConfigs();
    });
  }

  Future<void> _loadConfigs() async {
    setState(() => _isLoading = true);
    try {
      final configs = await _modeService.getAllConfigs();
      if (mounted) {
        setState(() {
          _configs = configs;
          _selectedMode = _selectedMode ?? MeetingMode.values.first;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load configs: $e')),
        );
      }
    }
  }

  Future<void> _saveConfig(MeetingModeConfig config) async {
    try {
      await _modeService.saveConfig(config);
      await _loadConfigs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save config: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Manage Meeting Modes'),
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surface,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Sidebar with mode list
                Container(
                  width: 250,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: ListView.builder(
                    itemCount: MeetingMode.values.length,
                    itemBuilder: (context, index) {
                      final mode = MeetingMode.values[index];
                      final isSelected = _selectedMode == mode;
                      return ListTile(
                        selected: isSelected,
                        leading: Icon(mode.icon),
                        title: Text(mode.label),
                        onTap: () {
                          setState(() => _selectedMode = mode);
                        },
                      );
                    },
                  ),
                ),
                // Main content area
                Expanded(
                  child: _selectedMode == null
                      ? const Center(child: Text('Select a mode to configure'))
                      : _buildModeEditor(_selectedMode!),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildModeEditor(MeetingMode mode) {
    final config = _configs[mode] ?? MeetingModeService.getDefaultConfig(mode);
    final realTimePromptController = TextEditingController(text: config.realTimePrompt);
    final notesTemplateController = TextEditingController(text: config.notesTemplate);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(mode.icon, size: 32),
              const SizedBox(width: 12),
              Text(
                mode.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Real-time Prompt section
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Real-time Prompt',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This prompt is used when asking AI questions during the meeting. It helps the AI understand the context and provide relevant responses.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TextField(
                              controller: realTimePromptController,
                              maxLines: null,
                              expands: true,
                              decoration: const InputDecoration(
                                hintText: 'Enter the real-time prompt for this mode...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Notes Template section
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.note, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Notes Template',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This template is used when generating notes for this meeting mode. Use markdown formatting for structure.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TextField(
                              controller: notesTemplateController,
                              maxLines: null,
                              expands: true,
                              decoration: const InputDecoration(
                                hintText: 'Enter the notes template for this mode...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () async {
                  // Reset to default
                  final defaultConfig = MeetingModeService.getDefaultConfig(mode);
                  realTimePromptController.text = defaultConfig.realTimePrompt;
                  notesTemplateController.text = defaultConfig.notesTemplate;
                  await _saveConfig(defaultConfig);
                },
                child: const Text('Reset to Default'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final updatedConfig = config.copyWith(
                    realTimePrompt: realTimePromptController.text,
                    notesTemplate: notesTemplateController.text,
                  );
                  await _saveConfig(updatedConfig);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
