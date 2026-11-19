import 'dart:js_interop';

@JS('eval')
external JSAny? _jsEval(JSString code);

void triggerWebSirenPulse() {
  try {
    const script = '''
      (function() {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (!AudioCtx) return;
        const ctx = window.__aegisAudioCtx || new AudioCtx();
        window.__aegisAudioCtx = ctx;
        if (ctx.state === 'suspended') {
          ctx.resume().catch(function(){});
        }
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sawtooth';
        const now = ctx.currentTime;
        osc.frequency.setValueAtTime(720, now);
        osc.frequency.linearRampToValueAtTime(1240, now + 0.35);
        osc.frequency.linearRampToValueAtTime(680, now + 0.72);

        gain.gain.setValueAtTime(0.001, now);
        gain.gain.exponentialRampToValueAtTime(0.35, now + 0.05);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.75);

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.76);
      })();
    ''';
    _jsEval(script.toJS);
  } catch (_) {}
}
