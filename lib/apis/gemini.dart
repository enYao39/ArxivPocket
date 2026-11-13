import 'package:arxiv/models/chat_message.dart';
import 'package:arxiv/models/paper.dart';
import 'package:dio/dio.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/services.dart' show rootBundle;

enum AiProvider {
  gemini,
  openAiCompatible;

  static AiProvider fromStored(dynamic value) {
    if (value?.toString() == openAiCompatible.name) {
      return openAiCompatible;
    }
    return gemini;
  }
}

class GeminiModelOption {
  const GeminiModelOption({required this.id, required this.label});

  final String id;
  final String label;

  factory GeminiModelOption.fallback() {
    return GeminiModelOption(
      id: Gemini.defaultModelName,
      label: labelFromModelName(Gemini.defaultModelName),
    );
  }

  factory GeminiModelOption.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    final baseModelId = json['baseModelId']?.toString() ?? '';
    final modelId = name.startsWith('models/')
        ? name.substring('models/'.length)
        : baseModelId.isNotEmpty
        ? baseModelId
        : name;

    return GeminiModelOption(
      id: modelId,
      label: json['displayName']?.toString() ?? labelFromModelName(modelId),
    );
  }

  static String labelFromModelName(String modelName) {
    final id = modelName.replaceFirst('models/', '');
    return id
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}

class Gemini {
  static const defaultModelName = 'gemini-2.5-flash';
  static const defaultOpenAiBaseUrl = 'https://api.openai.com/v1';
  static const defaultOpenAiModelName = 'gpt-4o-mini';
  static final _dio = Dio();

  final AiProvider provider;
  GenerativeModel? _model;
  ChatSession? _chatSession;

  String? _openAiBaseUrl;
  String? _openAiApiKey;
  String? _openAiModelName;
  final List<Map<String, String>> _openAiMessages = [];

  Gemini._internal(
    String apiKey,
    String systemPrompt,
    String modelName, {
    List<ChatMessage> history = const [],
    this.provider = AiProvider.gemini,
    String? baseUrl,
  }) {
    if (provider == AiProvider.gemini) {
      _model = GenerativeModel(
        apiKey: apiKey,
        model: modelName,
        systemInstruction: Content.system(systemPrompt),
        generationConfig: GenerationConfig(
          temperature: 1,
          topK: 64,
          topP: 0.95,
          maxOutputTokens: 8192,
          responseMimeType: 'text/plain',
        ),
      );

      _chatSession = _model!.startChat(history: _contentHistoryFor(history));
    } else {
      _openAiBaseUrl = normalizeBaseUrl(baseUrl);
      _openAiApiKey = apiKey;
      _openAiModelName = modelName;
      if (systemPrompt.trim().isNotEmpty) {
        _openAiMessages.add({'role': 'system', 'content': systemPrompt});
      }
      for (final message in history) {
        final content = message.content.trim();
        if (content.isEmpty || message.role == Role.system) continue;
        _openAiMessages.add({
          'role': message.role == Role.user ? 'user' : 'assistant',
          'content': content,
        });
      }
    }
  }

  static String normalizeBaseUrl(String? baseUrl) {
    final trimmed = (baseUrl ?? '').trim();
    if (trimmed.isEmpty) return defaultOpenAiBaseUrl;
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static Future<Gemini> newModel(
    String apiKey, {
    Paper? paper,
    String modelName = defaultModelName,
    List<ChatMessage> history = const [],
    AiProvider provider = AiProvider.gemini,
    String? baseUrl,
  }) async {
    final systemPrompt = paper != null
        ? await _getModelSystemMessage(paper)
        : await _getGeneralSystemMessage();
    return Gemini._internal(
      apiKey,
      systemPrompt,
      modelName,
      history: history,
      provider: provider,
      baseUrl: baseUrl,
    );
  }

  static List<Content> _contentHistoryFor(List<ChatMessage> messages) {
    final history = <Content>[];

    for (final message in messages) {
      final content = message.content.trim();
      if (content.isEmpty || message.role == Role.system) {
        continue;
      }

      if (message.role == Role.user) {
        history.add(Content.text(content));
      } else {
        history.add(Content.model([TextPart(content)]));
      }
    }

    return history;
  }

  static bool _isTextChatModel(Map<String, dynamic> rawModel) {
    final methods = rawModel['supportedGenerationMethods'];
    final supportsGenerateContent =
        methods is List && methods.contains('generateContent');

    if (!supportsGenerateContent) return false;

    final searchableFields = [
      rawModel['name'],
      rawModel['baseModelId'],
      rawModel['displayName'],
    ].whereType<String>().join(' ').toLowerCase();

    if (!searchableFields.contains('gemini-')) return false;

    const excludedTerms = [
      'antigravity',
      'agent',
      'audio',
      'computer use',
      'computer-use',
      'deep research',
      'embedding',
      'image',
      'imagen',
      'live',
      'lyria',
      'nano banana',
      'robotics',
      'tts',
      'veo',
      'vision',
    ];

    return !excludedTerms.any(searchableFields.contains);
  }

  static Future<List<GeminiModelOption>> listModels(
    String apiKey, {
    AiProvider provider = AiProvider.gemini,
    String? baseUrl,
    String? customModel,
  }) async {
    if (provider == AiProvider.openAiCompatible) {
      return _listOpenAiCompatibleModels(
        apiKey,
        baseUrl: baseUrl,
        customModel: customModel,
      );
    }

    try {
      final response = await _dio.get(
        'https://generativelanguage.googleapis.com/v1beta/models',
        queryParameters: {'key': apiKey},
      );
      final data = response.data;

      if (data is! Map<String, dynamic>) return [GeminiModelOption.fallback()];

      final rawModels = data['models'];
      if (rawModels is! List) return [GeminiModelOption.fallback()];

      final modelOptions =
          rawModels
              .whereType<Map>()
              .map((rawModel) => rawModel.cast<String, dynamic>())
              .where(_isTextChatModel)
              .map((rawModel) {
                return GeminiModelOption.fromJson(rawModel);
              })
              .where((modelOption) => modelOption.id.isNotEmpty)
              .toList()
            ..sort((first, second) => first.label.compareTo(second.label));

      return modelOptions.isEmpty
          ? [GeminiModelOption.fallback()]
          : modelOptions;
    } catch (e) {
      return [GeminiModelOption.fallback()];
    }
  }

  static Future<List<GeminiModelOption>> _listOpenAiCompatibleModels(
    String apiKey, {
    String? baseUrl,
    String? customModel,
  }) async {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrl);
    final trimmedCustom = customModel?.trim() ?? '';
    final fallbackId = trimmedCustom.isNotEmpty
        ? trimmedCustom
        : defaultOpenAiModelName;
    final fallbackOption = GeminiModelOption(
      id: fallbackId,
      label: fallbackId,
    );

    try {
      final headers = <String, String>{};
      if (apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      }

      final response = await _dio.get(
        '$normalizedBaseUrl/models',
        options: Options(headers: headers),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return [fallbackOption];

      final rawModels = data['data'];
      if (rawModels is! List) return [fallbackOption];

      final options = rawModels
          .whereType<Map>()
          .map((item) => item['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .map((id) => GeminiModelOption(id: id, label: id))
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));

      if (trimmedCustom.isNotEmpty &&
          !options.any((option) => option.id == trimmedCustom)) {
        options.insert(0, GeminiModelOption(id: trimmedCustom, label: trimmedCustom));
      }

      return options.isEmpty ? [fallbackOption] : options;
    } catch (_) {
      return [fallbackOption];
    }
  }

  Future<ChatMessage> sendMessage(String message) async {
    if (provider == AiProvider.openAiCompatible) {
      return _sendOpenAiMessage(message);
    }

    try {
      var content = Content.text(message);
      var response = await _chatSession!.sendMessage(content);
      return ChatMessage(Role.ai, response.text?.trim() ?? "");
    } catch (e) {
      return ChatMessage(Role.ai, e.toString());
    }
  }

  Future<ChatMessage> _sendOpenAiMessage(String message) async {
    try {
      _openAiMessages.add({'role': 'user', 'content': message});
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if ((_openAiApiKey ?? '').trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${_openAiApiKey!.trim()}';
      }

      final response = await _dio.post(
        '$_openAiBaseUrl/chat/completions',
        options: Options(headers: headers),
        data: {
          'model': _openAiModelName ?? defaultOpenAiModelName,
          'messages': _openAiMessages,
        },
      );

      final data = response.data;
      final choices = data is Map ? data['choices'] : null;
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        final msg = first is Map ? first['message'] : null;
        final text = (msg is Map ? msg['content']?.toString() : null) ?? '';
        final trimmed = text.trim();
        _openAiMessages.add({'role': 'assistant', 'content': trimmed});
        return ChatMessage(Role.ai, trimmed);
      }

      return ChatMessage(Role.ai, 'No response returned from AI provider.');
    } catch (e) {
      return ChatMessage(Role.ai, e.toString());
    }
  }

  static Future<String> _getModelSystemMessage(Paper paper) async {
    var substitutes = {
      'paperId': paper.id,
      'paperTitle': paper.title,
      'paperAuthors': paper.authors,
      'paperPublishedDate': paper.publishedAt,
      'paperSummary': paper.summary,
    };

    return await _fromTemplateFile(
      'assets/system_message_templates/model.txt',
      substitutes,
    );
  }

  static Future<String> _getGeneralSystemMessage() async {
    return await _fromTemplateFile(
      'assets/system_message_templates/general.txt',
      {},
    );
  }

  /// Interpolates values to a text read from a file. The format for a placeholder is {{some_name}}.
  static Future<String> _fromTemplateFile(
    String fileName,
    Map<String, dynamic> substitutes,
  ) async {
    var template = await rootBundle.loadString(fileName);
    return template.splitMapJoin(
      RegExp('{{.*?}}'),
      onMatch: (m) => substitutes[_getPlaceholderName(m.group(0))] ?? '',
    );
  }

  static String _getPlaceholderName(String? placeholderTemplate) {
    if (placeholderTemplate == null) return '';

    return placeholderTemplate.substring(2, placeholderTemplate.length - 2);
  }
}
