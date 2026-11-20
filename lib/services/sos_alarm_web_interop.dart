import 'dart:js_interop';
import 'package:web/web.dart' as web;

void triggerWebSirenPulse() {
  try {
    final ctx = web.AudioContext();
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();

    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(880, ctx.currentTime);
    osc.frequency.linearRampToValueAtTime(1320, ctx.currentTime + 0.35);
    osc.frequency.linearRampToValueAtTime(880, ctx.currentTime + 0.7);

    gain.gain.setValueAtTime(0.18, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.75);

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.start();
    osc.stop(ctx.currentTime + 0.76);
  } catch (_) {}
}

// Classic Mi-inspired melodic phone ringtone pattern (musical notes, not siren)
void triggerClassicPhoneRingtone() {
  try {
    final ctx = web.AudioContext();
    final notes = <double>[783.99, 1174.66, 987.77, 783.99, 880.0, 1318.51, 1108.73, 880.0];
    const stepDuration = 0.14;

    for (var i = 0; i < notes.length; i++) {
      final startTime = ctx.currentTime + (i * stepDuration);
      final endTime = startTime + (stepDuration * 0.88);

      final osc = ctx.createOscillator();
      final gain = ctx.createGain();

      osc.type = 'triangle';
      osc.frequency.setValueAtTime(notes[i], startTime);

      gain.gain.setValueAtTime(0.001, startTime);
      gain.gain.linearRampToValueAtTime(0.16, startTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, endTime);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start(startTime);
      osc.stop(endTime + 0.01);
    }
  } catch (_) {}
}
