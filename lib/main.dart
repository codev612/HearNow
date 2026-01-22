import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;
import 'providers/speech_to_text_provider.dart';
import 'providers/interview_provider.dart';
import 'services/ai_service.dart';
import 'config/app_config.dart';
import 'screens/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window manager for transparency and always-on-top (Windows only)
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      alwaysOnTop: true,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SpeechToTextProvider(),
        ),
        ChangeNotifierProxyProvider<SpeechToTextProvider, InterviewProvider>(
          create: (_) => InterviewProvider(
            aiService: AiService(
              httpBaseUrl: AppConfig.serverHttpBaseUrl,
              aiWsUrl: AppConfig.serverAiWebSocketUrl,
            ),
          ),
          update: (_, speechProvider, previous) => previous ??
              InterviewProvider(
                aiService: AiService(
                  httpBaseUrl: AppConfig.serverHttpBaseUrl,
                  aiWsUrl: AppConfig.serverAiWebSocketUrl,
                ),
              ),
        ),
      ],
      child: MaterialApp(
        title: 'HearNow',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
        ),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    );
  }
}


