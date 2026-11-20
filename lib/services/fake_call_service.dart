import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'sos_alarm_web_stub.dart'
    if (dart.library.js_interop) 'sos_alarm_web_interop.dart';

class FakeCallService {
  FakeCallService._();
  static final FakeCallService instance = FakeCallService._();

  Timer? _ringTimer;
  bool _isRinging = false;

  bool get isRinging => _isRinging;

  void startRingtone() {
    if (_isRinging) return;
    _isRinging = true;
    _pulse();
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isRinging) return;
      _pulse();
    });
  }

  void _pulse() {
    if (!kIsWeb) {
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
    }
    triggerWebSirenPulse();
  }

  void stopRingtone() {
    _isRinging = false;
    _ringTimer?.cancel();
    _ringTimer = null;
  }
}
