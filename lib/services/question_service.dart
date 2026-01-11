import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/question.dart';

class QuestionService {
  static const String _endpoint =
      'https://ysqoatnnjsbsimjknmen.supabase.co/functions/v1/generate_questions';

  Future<Question> fetchQuestion() async {
    final uri = Uri.parse(_endpoint);
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final options =
            (body['options'] as List?)?.cast<String>() ?? <String>[];
        return Question(
          id: body['id']?.toString() ?? DateTime.now().toIso8601String(),
          prompt: body['prompt'] as String? ?? 'What stood out the most?',
          options: options.isNotEmpty
              ? options
              : <String>['Option A', 'Option B'],
        );
      }
    } catch (_) {
      // Swallow and fall back to a local prompt if the API is not ready yet.
    }

    return const Question(
      id: 'fallback',
      prompt: 'What are the two key components for establishing neural connections?',
      options: <String>['PN & PC', 'CA & DA ', 'TV & RA'],
    );
  }
}
