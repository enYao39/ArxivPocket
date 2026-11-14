import 'package:flutter/services.dart';

class AospTtsService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.arxiv/aosp_tts',
  );

  static bool _handlerRegistered = false;
  static VoidCallback? _activeCompletionHandler;
  static ValueChanged<String>? _activeErrorHandler;

  VoidCallback? _completionHandler;
  ValueChanged<String>? _errorHandler;

  AospTtsService() {
    if (!_handlerRegistered) {
      _handlerRegistered = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onComplete') {
          _activeCompletionHandler?.call();
        } else if (call.method == 'onError') {
          _activeErrorHandler?.call(
            (call.arguments ?? 'Speech playback failed.').toString(),
          );
        }
      });
    }
  }

  void setCompletionHandler(VoidCallback handler) {
    _completionHandler = handler;
  }

  void setErrorHandler(ValueChanged<String> handler) {
    _errorHandler = handler;
  }

  Future<void> setLanguage(String language) async {
    try {
      await _channel.invokeMethod<bool>('setLanguage', {'language': language});
    } catch (_) {}
  }

  Future<void> setSpeechRate(double rate) async {
    try {
      await _channel.invokeMethod<bool>('setSpeechRate', {'rate': rate});
    } catch (_) {}
  }

  Future<bool> speak(String rawText) async {
    final cleaned = cleanTextForSpeech(rawText);
    if (cleaned.isEmpty) return false;

    _activeCompletionHandler = _completionHandler;
    _activeErrorHandler = _errorHandler;

    try {
      final ok = await _channel.invokeMethod<bool>('speak', {'text': cleaned});
      return ok ?? false;
    } on PlatformException catch (e) {
      _errorHandler?.call(
        e.message ?? 'No AOSP text-to-speech engine is available.',
      );
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  /// Cleans LaTeX, inline math delimiters, and Markdown so AOSP TTS reads naturally.
  static String cleanTextForSpeech(String input) {
    var text = input.trim();
    if (text.isEmpty) return '';

    text = text.replaceAll(r'\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
    // Unwrap common formatting commands like \textbf{word}, \emph{word}, \mathrm{x}.
    text = text.replaceAllMapped(
      RegExp(r'\\(?:textbf|textit|emph|mathrm|mathbf|mathit|text)\{([^}]*)\}'),
      (m) => m.group(1) ?? '',
    );
    // Strip display/inline math delimiters while keeping readable content.
    text = text
        .replaceAll(r'$$', ' ')
        .replaceAll(r'$', ' ')
        .replaceAll(r'\(', ' ')
        .replaceAll(r'\)', ' ')
        .replaceAll(r'\[', ' ')
        .replaceAll(r'\]', ' ');
    // Strip remaining LaTeX commands and braces.
    text = text
        .replaceAll(RegExp(r'\\[a-zA-Z]+'), ' ')
        .replaceAll(RegExp(r'[{}*_`#]'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
