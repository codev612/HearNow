class InterviewQuestionService {
  static const List<String> _generalQuestions = [
    'Tell me about yourself.',
    'What interests you about this role?',
    'Why do you want to work here?',
    'What are your strengths?',
    'What are your weaknesses?',
    'Where do you see yourself in 5 years?',
    'Why are you leaving your current position?',
    'What motivates you?',
    'How do you handle stress?',
    'Describe a challenging situation you faced.',
  ];

  static const List<String> _technicalQuestions = [
    'Can you walk me through your technical background?',
    'What programming languages are you most comfortable with?',
    'Describe a technical project you\'re proud of.',
    'How do you approach debugging?',
    'What\'s your experience with version control?',
    'How do you stay updated with technology?',
    'Describe your experience with testing.',
    'How do you handle technical disagreements?',
    'What tools do you use for development?',
    'Can you explain [technical concept]?',
  ];

  static const List<String> _behavioralQuestions = [
    'Tell me about a time you worked in a team.',
    'Describe a situation where you had to meet a tight deadline.',
    'Give an example of when you showed leadership.',
    'Tell me about a mistake you made and how you handled it.',
    'Describe a time you had to learn something new quickly.',
    'How do you handle conflict in the workplace?',
    'Tell me about a time you went above and beyond.',
    'Describe a situation where you had to adapt to change.',
    'Give an example of when you had to prioritize tasks.',
    'Tell me about a time you received constructive feedback.',
  ];

  static const List<String> _cultureFitQuestions = [
    'What type of work environment do you prefer?',
    'How do you prefer to communicate with teammates?',
    'What does work-life balance mean to you?',
    'How do you handle feedback?',
    'What values are important to you in a workplace?',
    'How do you contribute to team culture?',
    'What do you do outside of work?',
    'How do you approach continuous learning?',
    'What makes a team successful in your opinion?',
    'How do you handle ambiguity?',
  ];

  static List<String> getQuestionsByCategory(String category) {
    return switch (category.toLowerCase()) {
      'general' => _generalQuestions,
      'technical' => _technicalQuestions,
      'behavioral' => _behavioralQuestions,
      'culture' => _cultureFitQuestions,
      _ => _generalQuestions,
    };
  }

  static List<String> getAllQuestions() {
    return [
      ..._generalQuestions,
      ..._technicalQuestions,
      ..._behavioralQuestions,
      ..._cultureFitQuestions,
    ];
  }

  static List<String> getRandomQuestions(int count) {
    final all = getAllQuestions();
    all.shuffle();
    return all.take(count).toList();
  }

  static Map<String, List<String>> getQuestionsByCategoryMap() {
    return {
      'General': _generalQuestions,
      'Technical': _technicalQuestions,
      'Behavioral': _behavioralQuestions,
      'Culture Fit': _cultureFitQuestions,
    };
  }
}
