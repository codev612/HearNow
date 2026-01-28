/// User-created question template. Stored in local storage / DB.
class CustomQuestionTemplate {
  final String id;
  final String question;

  const CustomQuestionTemplate({
    required this.id,
    required this.question,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
      };

  factory CustomQuestionTemplate.fromJson(Map<String, dynamic> json) {
    return CustomQuestionTemplate(
      id: json['id'] as String,
      question: json['question'] as String? ?? '',
    );
  }

  CustomQuestionTemplate copyWith({
    String? id,
    String? question,
  }) {
    return CustomQuestionTemplate(
      id: id ?? this.id,
      question: question ?? this.question,
    );
  }
}
