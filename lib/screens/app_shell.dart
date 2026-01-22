import 'package:flutter/material.dart';

import 'home_page.dart';
import 'settings_page.dart';
import 'interview_page_enhanced.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 1; // default to Interview

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    onStartInterview: () => setState(() => _index = 1),
                  ),
                ),
                // Interview page remains transparent
                const InterviewPageEnhanced(),
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
            label: 'Interview',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
