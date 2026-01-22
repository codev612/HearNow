import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;

import 'home_page.dart';
import 'settings_page.dart';
import 'meeting_page_enhanced.dart';
import 'signin_page.dart';
import '../providers/shortcuts_provider.dart';
import '../providers/auth_provider.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // default to Home
  bool _wasAuthenticated = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        // Show signin page if not authenticated
        if (!authProvider.isAuthenticated) {
          _wasAuthenticated = false;
          return const SignInPage();
        }

        // Reset to home page when user just signed in
        if (!_wasAuthenticated && authProvider.isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _index = 0; // Go to home page after sign in
              });
            }
          });
        }
        _wasAuthenticated = true;

        return Consumer<ShortcutsProvider>(
          builder: (context, shortcutsProvider, child) {
        // Get toggle hide shortcut from provider
        final toggleHide = shortcutsProvider.getShortcutActivator('toggleHide');
        final shortcuts = <ShortcutActivator, Intent>{};
        if (Platform.isWindows && toggleHide != null) {
          shortcuts[toggleHide] = _ToggleHideIntent();
        }
        
        return Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: {
              if (Platform.isWindows)
                _ToggleHideIntent: CallbackAction<_ToggleHideIntent>(
                  onInvoke: (_) async {
                    if (Platform.isWindows) {
                      final isMinimized = await windowManager.isMinimized();
                      if (isMinimized) {
                        await windowManager.show();
                        await windowManager.focus();
                      } else {
                        await windowManager.minimize();
                      }
                    }
                    return null;
                  },
                ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
        children: [
          // Title bar background for visibility
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 32, // Standard Windows title bar height
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
          SafeArea(
            child: IndexedStack(
              index: _index,
              children: [
                // Home page with opaque background
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: HomePage(
                    onStartMeeting: () => setState(() => _index = 1),
                  ),
                ),
                // Meeting page remains transparent
                const MeetingPageEnhanced(),
                // Settings page with opaque background
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: const SettingsPage(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.record_voice_over_outlined),
            activeIcon: Icon(Icons.record_voice_over),
            label: 'Meeting',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
            ),
          ),
        ),
      );
        },
      );
      },
    );
  }
}

class _ToggleHideIntent extends Intent {
  const _ToggleHideIntent();
}
