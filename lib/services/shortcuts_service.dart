import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShortcutsService {
  static const String _prefsPrefix = 'shortcut_';
  
  // Default shortcuts
  static const Map<String, String> defaultShortcuts = {
    'toggleRecord': 'Control+KeyR',
    'askAi': 'Control+Enter',
    'saveSession': 'Control+KeyS',
    'exportSession': 'Control+KeyE',
    'markMoment': 'Control+KeyM',
    'toggleHide': 'Control+KeyH',
  };

  // Load shortcut from preferences
  static Future<String> getShortcut(String action) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefsPrefix$action') ?? defaultShortcuts[action] ?? '';
  }

  // Save shortcut to preferences
  static Future<void> setShortcut(String action, String shortcut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix$action', shortcut);
  }

  // Get all shortcuts
  static Future<Map<String, String>> getAllShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final shortcuts = <String, String>{};
    for (final action in defaultShortcuts.keys) {
      shortcuts[action] = prefs.getString('$_prefsPrefix$action') ?? defaultShortcuts[action]!;
    }
    return shortcuts;
  }

  // Reset all shortcuts to defaults
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in defaultShortcuts.entries) {
      await prefs.remove('$_prefsPrefix${entry.key}');
    }
  }

  // Parse shortcut string to ShortcutActivator
  static ShortcutActivator? parseShortcut(String shortcutString) {
    if (shortcutString.isEmpty) return null;
    
    final parts = shortcutString.split('+');
    bool control = false;
    bool shift = false;
    bool alt = false;
    bool meta = false;
    LogicalKeyboardKey? key;

    for (final part in parts) {
      final trimmed = part.trim();
      switch (trimmed.toLowerCase()) {
        case 'control':
        case 'ctrl':
          control = true;
          break;
        case 'shift':
          shift = true;
          break;
        case 'alt':
          alt = true;
          break;
        case 'meta':
        case 'cmd':
          meta = true;
          break;
        default:
          // Try to parse as key
          if (trimmed == 'Enter') {
            key = LogicalKeyboardKey.enter;
          } else if (trimmed == 'Space') {
            key = LogicalKeyboardKey.space;
          } else if (trimmed == 'Escape') {
            key = LogicalKeyboardKey.escape;
          } else if (trimmed.startsWith('Key')) {
            final keyName = trimmed.substring(3);
            key = _parseKeyName(keyName);
          } else {
            key = _parseKeyName(trimmed);
          }
      }
    }

    if (key == null) return null;

    return SingleActivator(
      key,
      control: control,
      shift: shift,
      alt: alt,
      meta: meta,
    );
  }

  // Format ShortcutActivator to string
  static String formatShortcut(ShortcutActivator activator) {
    if (activator is! SingleActivator) return '';
    
    final parts = <String>[];
    if (activator.control) parts.add('Control');
    if (activator.shift) parts.add('Shift');
    if (activator.alt) parts.add('Alt');
    if (activator.meta) parts.add('Meta');
    
    // SingleActivator uses 'trigger' property to access the key
    final key = activator.trigger;
    parts.add(_formatKey(key));
    return parts.join('+');
  }

  static LogicalKeyboardKey? _parseKeyName(String name) {
    switch (name.toUpperCase()) {
      case 'A': return LogicalKeyboardKey.keyA;
      case 'B': return LogicalKeyboardKey.keyB;
      case 'C': return LogicalKeyboardKey.keyC;
      case 'D': return LogicalKeyboardKey.keyD;
      case 'E': return LogicalKeyboardKey.keyE;
      case 'F': return LogicalKeyboardKey.keyF;
      case 'G': return LogicalKeyboardKey.keyG;
      case 'H': return LogicalKeyboardKey.keyH;
      case 'I': return LogicalKeyboardKey.keyI;
      case 'J': return LogicalKeyboardKey.keyJ;
      case 'K': return LogicalKeyboardKey.keyK;
      case 'L': return LogicalKeyboardKey.keyL;
      case 'M': return LogicalKeyboardKey.keyM;
      case 'N': return LogicalKeyboardKey.keyN;
      case 'O': return LogicalKeyboardKey.keyO;
      case 'P': return LogicalKeyboardKey.keyP;
      case 'Q': return LogicalKeyboardKey.keyQ;
      case 'R': return LogicalKeyboardKey.keyR;
      case 'S': return LogicalKeyboardKey.keyS;
      case 'T': return LogicalKeyboardKey.keyT;
      case 'U': return LogicalKeyboardKey.keyU;
      case 'V': return LogicalKeyboardKey.keyV;
      case 'W': return LogicalKeyboardKey.keyW;
      case 'X': return LogicalKeyboardKey.keyX;
      case 'Y': return LogicalKeyboardKey.keyY;
      case 'Z': return LogicalKeyboardKey.keyZ;
      default: return null;
    }
  }

  static String _formatKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.escape) return 'Escape';
    
    final keyString = key.keyLabel.toUpperCase();
    if (keyString.length == 1 && keyString.codeUnitAt(0) >= 65 && keyString.codeUnitAt(0) <= 90) {
      return 'Key$keyString';
    }
    return keyString;
  }
}
