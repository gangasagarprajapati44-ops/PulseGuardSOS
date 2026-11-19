import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'sos_alarm_web_stub.dart'
    if (dart.library.js_interop) 'sos_alarm_web_interop.dart';

class SosAlarmService {
  SosAlarmService._();
  static final SosAlarmService instance = SosAlarmService._();

  Timer? _sirenTimer;
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  void startEmergencySiren() {
    if (_isPlaying) return;
    _isPlaying = true;

    _playSirenPulse();
    _sirenTimer?.cancel();
    _sirenTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!_isPlaying) return;
      _playSirenPulse();
    });
  }

  void _playSirenPulse() {
    if (!kIsWeb) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
    triggerWebSirenPulse();
  }

  void stopEmergencySiren() {
    _isPlaying = false;
    _sirenTimer?.cancel();
    _sirenTimer = null;
  }
}
