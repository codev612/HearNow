import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shortcuts_service.dart';

class ShortcutsProvider extends ChangeNotifier {
  Map<String, String> _shortcuts = {};
  bool _isLoading = false;

  Map<String, String> get shortcuts => Map.unmodifiable(_shortcuts);
  bool get isLoading => _isLoading;

  ShortcutsProvider() {
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    _isLoading = true;
    notifyListeners();
    
    _shortcuts = await ShortcutsService.getAllShortcuts();
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setShortcut(String action, String shortcut) async {
    await ShortcutsService.setShortcut(action, shortcut);
    _shortcuts[action] = shortcut;
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await ShortcutsService.resetToDefaults();
    await _loadShortcuts();
  }

  String getShortcut(String action) {
    return _shortcuts[action] ?? ShortcutsService.defaultShortcuts[action] ?? '';
  }

  ShortcutActivator? getShortcutActivator(String action) {
    final shortcutString = getShortcut(action);
    return ShortcutsService.parseShortcut(shortcutString);
  }
}
