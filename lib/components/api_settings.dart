// ignore_for_file: file_names

import 'package:arxiv/apis/gemini.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

class APISettings extends StatefulWidget {
  const APISettings({super.key, required this.configAPIKey});

  final Function configAPIKey;

  @override
  State<APISettings> createState() => _APISettingsState();
}

class _APISettingsState extends State<APISettings> {
  final TextEditingController apiKeyController = TextEditingController();
  final TextEditingController baseUrlController = TextEditingController();
  final TextEditingController customModelController = TextEditingController();

  final googleAIStudioURL = "https://aistudio.google.com/app/apikey";
  AiProvider provider = AiProvider.gemini;
  var apiKey = "";
  var baseUrl = "";
  var customModel = "";

  @override
  void initState() {
    super.initState();
    getSavedAPIKey();
  }

  @override
  void dispose() {
    apiKeyController.dispose();
    baseUrlController.dispose();
    customModelController.dispose();
    super.dispose();
  }

  void getAPIKey() async {
    await launchUrl(Uri.parse(googleAIStudioURL));
  }

  Future<void> saveAPIKey() async {
    final newAPIKey = apiKeyController.text.trim();
    final newBaseUrl = baseUrlController.text.trim();
    final newCustomModel = customModelController.text.trim();

    Box apiBox = await Hive.openBox("apibox");
    await apiBox.put("provider", provider.name);
    if (newAPIKey.isNotEmpty) {
      await apiBox.put("apikey", newAPIKey);
      apiKey = newAPIKey;
    } else if (provider == AiProvider.openAiCompatible && apiKey.isEmpty) {
      // Allow empty API key for local OpenAI-compatible servers (e.g. Ollama).
      await apiBox.put("apikey", "");
    }
    await apiBox.put(
      "baseUrl",
      newBaseUrl.isNotEmpty ? newBaseUrl : Gemini.defaultOpenAiBaseUrl,
    );
    await apiBox.put("customModel", newCustomModel);

    widget.configAPIKey();
  }

  Future<void> clearAPIKey() async {
    apiKey = "";
    apiKeyController.clear();
    Box apiBox = await Hive.openBox("apibox");
    await apiBox.put("apikey", "");
    await apiBox.put("customModel", "");
    widget.configAPIKey();
  }

  Future<void> getSavedAPIKey() async {
    Box apiBox = await Hive.openBox("apibox");
    provider = AiProvider.fromStored(await apiBox.get("provider"));
    apiKey = await apiBox.get("apikey") ?? "";
    baseUrl = await apiBox.get("baseUrl") ?? Gemini.defaultOpenAiBaseUrl;
    customModel = await apiBox.get("customModel") ?? "";

    baseUrlController.text = baseUrl;
    customModelController.text = customModel;
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.only(left: 18.0, right: 12.0),
      margin: const EdgeInsets.only(bottom: 10.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30.0),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: TextField(
        controller: controller,
        cursorColor: colorScheme.primary,
        style: TextStyle(color: colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildActionChipButton(
    String label,
    VoidCallback onTap,
    ColorScheme colorScheme,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGemini = provider == AiProvider.gemini;

    return Padding(
      padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 12.0),
      child: Column(
        children: [
          Wrap(
            spacing: 8.0,
            alignment: WrapAlignment.center,
            children: [
              ChoiceChip(
                label: const Text("Google Gemini"),
                selected: isGemini,
                onSelected: (_) {
                  setState(() {
                    provider = AiProvider.gemini;
                  });
                },
              ),
              ChoiceChip(
                label: const Text("OpenAI-Compatible"),
                selected: !isGemini,
                onSelected: (_) {
                  setState(() {
                    provider = AiProvider.openAiCompatible;
                  });
                },
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 10.0,
            ),
            child: Text(
              isGemini
                  ? "Enter a Google AI Studio API key to chat with Gemini models (2.5 Flash, 2.5 Pro, and newer)."
                  : "Connect any OpenAI-compatible API (OpenAI, OpenRouter, DeepSeek, Groq, or local Ollama/LM Studio).",
              textAlign: TextAlign.center,
            ),
          ),
          if (!isGemini) ...[
            _buildInputField(
              controller: baseUrlController,
              hintText: "Base URL (e.g. https://api.openai.com/v1)",
              colorScheme: colorScheme,
            ),
            _buildInputField(
              controller: customModelController,
              hintText: "Model ID (optional, e.g. gpt-4o-mini)",
              colorScheme: colorScheme,
            ),
          ],
          _buildInputField(
            controller: apiKeyController,
            hintText: apiKey.isEmpty
                ? (isGemini
                      ? "Enter API key here..."
                      : "API key (optional for local servers)...")
                : apiKey,
            colorScheme: colorScheme,
          ),
          Wrap(
            spacing: 10.0,
            alignment: WrapAlignment.center,
            children: [
              if (isGemini)
                _buildActionChipButton("Get API Key", getAPIKey, colorScheme),
              _buildActionChipButton("Save", saveAPIKey, colorScheme),
              _buildActionChipButton("Clear Key", clearAPIKey, colorScheme),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(top: 40.0, left: 28.0, right: 28.0),
            child: Text(
              isGemini
                  ? "Model availability and rate limits depend on your Google AI Studio tier (free or paid). Paid-tier API requests are not used to improve Google products."
                  : "Your API key and endpoint URL are stored locally on this device and sent only to the provider you configure.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
