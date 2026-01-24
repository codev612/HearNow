import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meeting_mode.dart';
import '../config/app_config.dart';

class MeetingModeConfig {
  final MeetingMode mode;
  final String realTimePrompt;
  final String notesTemplate;

  MeetingModeConfig({
    required this.mode,
    required this.realTimePrompt,
    required this.notesTemplate,
  });

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'realTimePrompt': realTimePrompt,
      'notesTemplate': notesTemplate,
    };
  }

  factory MeetingModeConfig.fromJson(Map<String, dynamic> json) {
    return MeetingModeConfig(
      mode: MeetingMode.fromString(json['mode'] as String?),
      realTimePrompt: json['realTimePrompt'] as String? ?? '',
      notesTemplate: json['notesTemplate'] as String? ?? '',
    );
  }

  MeetingModeConfig copyWith({
    String? realTimePrompt,
    String? notesTemplate,
  }) {
    return MeetingModeConfig(
      mode: mode,
      realTimePrompt: realTimePrompt ?? this.realTimePrompt,
      notesTemplate: notesTemplate ?? this.notesTemplate,
    );
  }
}

class MeetingModeService {
  static const String _configsKey = 'meeting_mode_configs';
  String? _authToken;
  
  String? get authToken => _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
  }

  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  String _getApiUrl(String path) {
    final base = AppConfig.serverHttpBaseUrl;
    final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$cleanBase$cleanPath';
  }

  Future<Map<MeetingMode, MeetingModeConfig>> getAllConfigs() async {
    // Try to load from database first
    if (_authToken != null && _authToken!.isNotEmpty) {
      try {
        final url = _getApiUrl('/api/mode-configs');
        final response = await http.get(
          Uri.parse(url),
          headers: _getHeaders(),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final configs = <MeetingMode, MeetingModeConfig>{};
          
          for (final mode in MeetingMode.values) {
            if (data.containsKey(mode.name)) {
              final configData = data[mode.name] as Map<String, dynamic>;
              configs[mode] = MeetingModeConfig.fromJson({
                'mode': mode.name,
                ...configData,
              });
            } else {
              configs[mode] = getDefaultConfig(mode);
            }
          }
          
          // Cache in SharedPreferences
          await _cacheConfigs(configs);
          return configs;
        } else if (response.statusCode == 404) {
          // No configs in DB yet, use defaults and cache them
          final defaults = _getDefaultConfigs();
          await _cacheConfigs(defaults);
          return defaults;
        }
      } catch (e) {
        // Fall through to local cache/defaults
        print('Failed to load configs from DB: $e');
      }
    }
    
    // Fallback to local cache
    return await _loadCachedConfigs();
  }

  Future<void> saveConfig(MeetingModeConfig config) async {
    // Save to database
    if (_authToken != null && _authToken!.isNotEmpty) {
      try {
        final url = _getApiUrl('/api/mode-configs/${config.mode.name}');
        final response = await http.put(
          Uri.parse(url),
          headers: _getHeaders(),
          body: jsonEncode(config.toJson()),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          // Successfully saved to DB, update cache
          final allConfigs = await getAllConfigs();
          allConfigs[config.mode] = config;
          await _cacheConfigs(allConfigs);
          return;
        } else {
          throw Exception('Failed to save config: ${response.statusCode}');
        }
      } catch (e) {
        // Fall through to local cache
        print('Failed to save config to DB: $e');
      }
    }
    
    // Fallback to local cache
    final prefs = await SharedPreferences.getInstance();
    final allConfigs = await _loadCachedConfigs();
    allConfigs[config.mode] = config;
    await _cacheConfigs(allConfigs);
  }

  Future<MeetingModeConfig> getConfig(MeetingMode mode) async {
    final configs = await getAllConfigs();
    return configs[mode] ?? getDefaultConfig(mode);
  }

  Future<Map<MeetingMode, MeetingModeConfig>> _loadCachedConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getString(_configsKey);
    
    if (configsJson == null) {
      return _getDefaultConfigs();
    }

    try {
      final Map<String, dynamic> decoded = jsonDecode(configsJson) as Map<String, dynamic>;
      
      final configs = <MeetingMode, MeetingModeConfig>{};
      for (final mode in MeetingMode.values) {
        if (decoded.containsKey(mode.name)) {
          final configData = decoded[mode.name] as Map<String, dynamic>;
          configs[mode] = MeetingModeConfig.fromJson({
            'mode': mode.name,
            ...configData,
          });
        } else {
          configs[mode] = getDefaultConfig(mode);
        }
      }
      return configs;
    } catch (e) {
      return _getDefaultConfigs();
    }
  }

  Future<void> _cacheConfigs(Map<MeetingMode, MeetingModeConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final configsMap = configs.map((key, value) => 
      MapEntry(key.name, value.toJson())
    );
    await prefs.setString(_configsKey, jsonEncode(configsMap));
  }

  static MeetingModeConfig getDefaultConfig(MeetingMode mode) {
    switch (mode) {
      case MeetingMode.general:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are a helpful assistant. Provide concise, relevant responses based on the conversation.',
          notesTemplate: '## Meeting Notes\n\n### Key Points\n- \n\n### Action Items\n- \n\n### Next Steps\n- ',
        );
      case MeetingMode.interview:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are an interview assistant. Help identify key candidate qualifications, strengths, and areas of concern. Ask relevant follow-up questions.',
          notesTemplate: '## Interview Notes\n\n### Candidate Information\n- Name: \n- Position: \n\n### Key Qualifications\n- \n\n### Strengths\n- \n\n### Areas of Concern\n- \n\n### Recommendation\n',
        );
      case MeetingMode.presentation:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are a presentation assistant. Help summarize key points, identify questions from the audience, and suggest clarifications.',
          notesTemplate: '## Presentation Notes\n\n### Topic\n\n### Key Points\n- \n\n### Questions Raised\n- \n\n### Feedback\n- ',
        );
      case MeetingMode.discussion:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are a discussion facilitator. Help identify main topics, summarize different viewpoints, and highlight decisions made.',
          notesTemplate: '## Discussion Notes\n\n### Topics Discussed\n- \n\n### Viewpoints\n- \n\n### Decisions Made\n- \n\n### Open Questions\n- ',
        );
      case MeetingMode.lecture:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are a lecture assistant. Help summarize main concepts, identify important examples, and note questions from students.',
          notesTemplate: '## Lecture Notes\n\n### Topic\n\n### Main Concepts\n- \n\n### Examples\n- \n\n### Questions\n- ',
        );
      case MeetingMode.meeting:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are a meeting assistant. Help track agenda items, summarize discussions, and identify action items and decisions.',
          notesTemplate: '## Meeting Notes\n\n### Agenda\n- \n\n### Discussion\n- \n\n### Decisions\n- \n\n### Action Items\n- ',
        );
      case MeetingMode.call:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are a call assistant. Help summarize the conversation, identify important information exchanged, and note follow-ups.',
          notesTemplate: '## Call Notes\n\n### Participants\n- \n\n### Topics Discussed\n- \n\n### Key Information\n- \n\n### Follow-ups\n- ',
        );
      case MeetingMode.other:
        return MeetingModeConfig(
          mode: mode,
          realTimePrompt: 'You are a helpful assistant. Provide concise, relevant responses based on the conversation.',
          notesTemplate: '## Notes\n\n### Summary\n\n### Key Points\n- \n\n### Action Items\n- ',
        );
    }
  }

  static Map<MeetingMode, MeetingModeConfig> _getDefaultConfigs() {
    return {
      for (final mode in MeetingMode.values)
        mode: getDefaultConfig(mode),
    };
  }
}
