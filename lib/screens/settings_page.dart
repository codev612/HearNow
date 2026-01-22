import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;

import '../config/app_config.dart';
import '../providers/shortcuts_provider.dart';
import '../services/shortcuts_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left sidebar
        Container(
          width: 200,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              right: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: _buildSidebar(),
        ),
        // Main content area
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SidebarItem(
          icon: Icons.keyboard,
          label: 'Shortcuts',
          isSelected: _selectedIndex == 0,
          onTap: () => setState(() => _selectedIndex = 0),
        ),
        _SidebarItem(
          icon: Icons.link,
          label: 'Connection',
          isSelected: _selectedIndex == 1,
          onTap: () => setState(() => _selectedIndex = 1),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Consumer<ShortcutsProvider>(
      builder: (context, shortcutsProvider, child) {
        switch (_selectedIndex) {
          case 0:
            return _buildShortcutsContent(shortcutsProvider);
          case 1:
            return _buildConnectionContent();
          default:
            return _buildShortcutsContent(shortcutsProvider);
        }
      },
    );
  }

  Widget _buildShortcutsContent(ShortcutsProvider shortcutsProvider) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text(
              'Keyboard Shortcuts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await shortcutsProvider.resetToDefaults();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Shortcuts reset to defaults')),
                  );
                }
              },
              child: const Text('Reset to Defaults'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ShortcutTile(
          label: 'Toggle Record',
          action: 'toggleRecord',
          shortcutsProvider: shortcutsProvider,
        ),
        _ShortcutTile(
          label: 'Ask AI',
          action: 'askAi',
          shortcutsProvider: shortcutsProvider,
        ),
        _ShortcutTile(
          label: 'Save Session',
          action: 'saveSession',
          shortcutsProvider: shortcutsProvider,
        ),
        _ShortcutTile(
          label: 'Export Session',
          action: 'exportSession',
          shortcutsProvider: shortcutsProvider,
        ),
        _ShortcutTile(
          label: 'Mark Moment',
          action: 'markMoment',
          shortcutsProvider: shortcutsProvider,
        ),
        if (Platform.isWindows)
          _ShortcutTile(
            label: 'Toggle Hide/Show',
            action: 'toggleHide',
            shortcutsProvider: shortcutsProvider,
          ),
      ],
    );
  }

  Widget _buildConnectionContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Connection',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('WebSocket URL'),
          subtitle: Text(AppConfig.serverWebSocketUrl),
          trailing: IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: AppConfig.serverWebSocketUrl),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Server URL copied')),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          border: isSelected
              ? Border(
                  right: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatefulWidget {
  final String label;
  final String action;
  final ShortcutsProvider shortcutsProvider;

  const _ShortcutTile({
    required this.label,
    required this.action,
    required this.shortcutsProvider,
  });

  @override
  State<_ShortcutTile> createState() => _ShortcutTileState();
}

class _ShortcutTileState extends State<_ShortcutTile> {
  bool _isCapturing = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _captureShortcut() async {
    setState(() => _isCapturing = true);
    
    final shortcut = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ShortcutCaptureDialog(
        currentShortcut: widget.shortcutsProvider.getShortcut(widget.action),
      ),
    );
    
    setState(() => _isCapturing = false);
    
    if (shortcut != null && shortcut.isNotEmpty) {
      await widget.shortcutsProvider.setShortcut(widget.action, shortcut);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shortcut updated: $shortcut')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortcutString = widget.shortcutsProvider.getShortcut(widget.action);
    
    return ListTile(
      leading: const Icon(Icons.keyboard),
      title: Text(widget.label),
      subtitle: Text(
        shortcutString.isEmpty ? 'Not set' : shortcutString,
        style: TextStyle(
          color: shortcutString.isEmpty 
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.primary,
          fontFamily: 'monospace',
        ),
      ),
      trailing: _isCapturing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit shortcut',
              onPressed: _captureShortcut,
            ),
    );
  }
}

class _ShortcutCaptureDialog extends StatefulWidget {
  final String currentShortcut;

  const _ShortcutCaptureDialog({required this.currentShortcut});

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  String _capturedShortcut = '';
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String _formatKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return '';
    
    final parts = <String>[];
    final keyboardState = HardwareKeyboard.instance;
    
    if (keyboardState.isControlPressed) parts.add('Control');
    if (keyboardState.isShiftPressed) parts.add('Shift');
    if (keyboardState.isAltPressed) parts.add('Alt');
    if (keyboardState.isMetaPressed) parts.add('Meta');
    
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      parts.add('Enter');
    } else if (event.logicalKey == LogicalKeyboardKey.space) {
      parts.add('Space');
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      parts.add('Escape');
    } else {
      final keyLabel = event.logicalKey.keyLabel.toUpperCase();
      if (keyLabel.length == 1 && keyLabel.codeUnitAt(0) >= 65 && keyLabel.codeUnitAt(0) <= 90) {
        parts.add('Key$keyLabel');
      } else {
        parts.add(keyLabel);
      }
    }
    
    return parts.join('+');
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final shortcut = _formatKeyEvent(event);
          if (shortcut.isNotEmpty && !shortcut.contains('Escape')) {
            setState(() => _capturedShortcut = shortcut);
          }
        }
      },
      child: AlertDialog(
        title: const Text('Capture Shortcut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Press the key combination for "${widget.currentShortcut}"'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Text(
                _capturedShortcut.isEmpty ? 'Press keys...' : _capturedShortcut,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'monospace',
                  color: _capturedShortcut.isEmpty
                      ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current: ${widget.currentShortcut.isEmpty ? "Not set" : widget.currentShortcut}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: _capturedShortcut.isEmpty
                ? null
                : () => Navigator.of(context).pop(_capturedShortcut),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
