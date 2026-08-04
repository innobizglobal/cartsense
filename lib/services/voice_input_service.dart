import 'package:flutter/services.dart';

class VoiceInputException implements Exception {
  const VoiceInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VoiceInputService {
  static const _channel = MethodChannel('cartsense/speech_input');

  Future<String?> listen({String languageCode = 'en'}) async {
    try {
      final result = await _channel.invokeMethod<String>('listen', {
        'language': _androidLocale(languageCode),
      });
      final text = result?.trim();
      return text == null || text.isEmpty ? null : text;
    } on MissingPluginException {
      throw const VoiceInputException(
        'Voice input is available on the Android app build.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') return null;
      throw VoiceInputException(
        error.message ?? 'Voice input could not be started on this phone.',
      );
    }
  }

  String _androidLocale(String languageCode) {
    switch (languageCode) {
      case 'hi':
        return 'hi-IN';
      case 'te':
        return 'te-IN';
      default:
        return 'en-IN';
    }
  }
}
