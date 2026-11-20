import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceSosService {
  VoiceSosService._();
  static final VoiceSosService instance = VoiceSosService._();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  int _needHelpCount = 0;
  DateTime? _firstMatchAt;

  bool get isListening => _isListening;

  Future<bool> startListening({
    required void Function(String status) onStatus,
    required Future<void> Function() onDoubleNeedHelp,
  }) async {
    if (!_isInitialized) {
      _isInitialized = await _speech.initialize(
        onStatus: (status) => onStatus('VOICE: ${status.toUpperCase()}'),
        onError: (_) => onStatus('VOICE: MIC ERROR / PERMISSION'),
      );
    }

    if (!_isInitialized) {
      onStatus('VOICE: UNAVAILABLE ON DEVICE');
      return false;
    }

    _needHelpCount = 0;
    _firstMatchAt = null;
    _isListening = true;
    onStatus('VOICE ARMED • SAY "NEED HELP" x2');

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) async {
        final spoken = result.recognizedWords.toLowerCase();
        if (!spoken.contains('need help')) return;

        final now = DateTime.now();
        if (_firstMatchAt == null ||
            now.difference(_firstMatchAt!) > const Duration(seconds: 7)) {
          _firstMatchAt = now;
          _needHelpCount = 1;
          onStatus('VOICE: "NEED HELP" 1/2 DETECTED');
          return;
        }

        _needHelpCount++;
        if (_needHelpCount >= 2) {
          _needHelpCount = 0;
          _firstMatchAt = null;
          onStatus('VOICE: 2x "NEED HELP" -> SOS TRIGGERED!');
          await stopListening(onStatus: (_) {});
          await onDoubleNeedHelp();
        }
      },
    );

    return true;
  }

  Future<void> stopListening({
    required void Function(String status) onStatus,
  }) async {
    _isListening = false;
    _needHelpCount = 0;
    _firstMatchAt = null;
    if (_speech.isListening) {
      await _speech.stop();
    }
    onStatus('VOICE: STANDBY');
  }
}
