import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/custom_question_template.dart';
import '../services/meeting_question_service.dart';
import '../providers/auth_provider.dart';

String _nextId() => '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';

class ManageQuestionTemplatesPage extends StatefulWidget {
  const ManageQuestionTemplatesPage({super.key});

  @override
  State<ManageQuestionTemplatesPage> createState() => _ManageQuestionTemplatesPageState();
}

class _ManageQuestionTemplatesPageState extends State<ManageQuestionTemplatesPage> {
  final MeetingQuestionService _questionService = MeetingQuestionService();
  List<CustomQuestionTemplate> _templates = [];
  bool _isLoading = true;
  CustomQuestionTemplate? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      _questionService.setAuthToken(authProvider.token);
      _loadAll();
    });
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final templates = await _questionService.getCustomTemplates();
      if (mounted) {
        setState(() {
          _templates = templates;
          _selected ??= templates.isNotEmpty ? templates.first : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: $e')),
        );
      }
    }
  }

  Future<void> _saveTemplate(CustomQuestionTemplate template, {bool silent = false}) async {
    try {
      print('[ManageQuestionTemplates] Saving template: id=${template.id}, question="${template.question}"');
      await _questionService.updateCustomTemplate(template);
      print('[ManageQuestionTemplates] Template saved successfully');
      if (mounted) {
        setState(() {
          final i = _templates.indexWhere((t) => t.id == template.id);
          if (i >= 0) {
            _templates[i] = template;
          } else {
            _templates.add(template);
          }
          if (!silent || _selected?.id == template.id) {
            _selected = template;
          }
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Question template saved')),
          );
        }
      }
    } catch (e, stackTrace) {
      print('[ManageQuestionTemplates] Error saving template: $e');
      print('[ManageQuestionTemplates] Stack trace: $stackTrace');
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _deleteTemplate(CustomQuestionTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Question Template'),
        content: Text('Are you sure you want to delete "${template.question}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _questionService.deleteCustomTemplate(template.id);
      if (mounted) {
        setState(() {
          _templates.removeWhere((t) => t.id == template.id);
          if (_selected?.id == template.id) {
            _selected = _templates.isNotEmpty ? _templates.first : null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question template deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> _addNewTemplate() async {
    final newTemplate = CustomQuestionTemplate(
      id: _nextId(),
      question: '',
    );
    setState(() {
      _templates.add(newTemplate);
      _selected = newTemplate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Manage Question Templates'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Left sidebar - list of templates
                Container(
                  width: 300,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevatedButton.icon(
                          onPressed: _addNewTemplate,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Template'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _templates.length,
                          itemBuilder: (context, index) {
                            final template = _templates[index];
                            final isSelected = _selected?.id == template.id;
                            return ListTile(
                              selected: isSelected,
                              title: Text(
                                template.question.isEmpty ? '(Empty)' : template.question,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => setState(() => _selected = template),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 20),
                                onPressed: () => _deleteTemplate(template),
                                tooltip: 'Delete',
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Right side - editor
                Expanded(
                  child: _selected == null
                      ? const Center(
                          child: Text('Select a template to edit, or add a new one'),
                        )
                      : _QuestionTemplateEditor(
                          template: _selected!,
                          onSave: (template) => _saveTemplate(template),
                        ),
                ),
              ],
            ),
    );
  }
}

class _QuestionTemplateEditor extends StatefulWidget {
  final CustomQuestionTemplate template;
  final Function(CustomQuestionTemplate) onSave;

  const _QuestionTemplateEditor({
    required this.template,
    required this.onSave,
  });

  @override
  State<_QuestionTemplateEditor> createState() => _QuestionTemplateEditorState();
}

class _QuestionTemplateEditorState extends State<_QuestionTemplateEditor> {
  late TextEditingController _questionController;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.template.question);
    _questionController.addListener(() {
      if (!_hasChanges) {
        setState(() => _hasChanges = true);
      }
    });
  }

  @override
  void didUpdateWidget(_QuestionTemplateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template.id != widget.template.id) {
      _questionController.text = widget.template.question;
      _hasChanges = false;
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  void _save() {
    final questionText = _questionController.text.trim();
    if (questionText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question cannot be empty')),
      );
      return;
    }
    final updated = widget.template.copyWith(
      question: questionText,
    );
    widget.onSave(updated);
    setState(() => _hasChanges = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit Question Template',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _questionController,
            decoration: const InputDecoration(
              labelText: 'Question',
              hintText: 'Enter your question template',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton(
                onPressed: _hasChanges ? _save : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
