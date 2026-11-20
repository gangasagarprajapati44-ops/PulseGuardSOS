import 'dart:async';
import 'package:flutter/material.dart';
import '../services/fake_call_service.dart';

class FakeCallScreen extends StatefulWidget {
  final String callerName;
  final String callerNumber;

  const FakeCallScreen({
    super.key,
    this.callerName = 'DAD (GUARDIAN)',
    this.callerNumber = '+91 98XXX XXXXX',
  });

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen> {
  bool _isConnected = false;
  int _secondsElapsed = 0;
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    FakeCallService.instance.startRingtone();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    FakeCallService.instance.stopRingtone();
    super.dispose();
  }

  void _acceptCall() {
    FakeCallService.instance.stopRingtone();
    setState(() {
      _isConnected = true;
      _secondsElapsed = 0;
    });
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsElapsed++);
    });
  }

  void _endOrDeclineCall() {
    _callTimer?.cancel();
    FakeCallService.instance.stopRingtone();
    Navigator.of(context).pop();
  }

  String _formattedDuration() {
    final mins = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final secs = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Text(
                    _isConnected ? 'CALL CONNECTED' : 'INCOMING CALL...',
                    style: const TextStyle(
                      color: Color(0xFF00F0FF),
                      letterSpacing: 1.5,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const CircleAvatar(
                    radius: 48,
                    backgroundColor: Color(0xFF162232),
                    child: Icon(
                      Icons.person,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.callerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.callerNumber,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _isConnected
                        ? _formattedDuration()
                        : 'Classic Ringtone • Ringing...',
                    style: TextStyle(
                      color: _isConnected
                          ? const Color(0xFF64FFDA)
                          : Colors.white54,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (!_isConnected)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        FloatingActionButton(
                          heroTag: 'decline_fake_call',
                          backgroundColor: const Color(0xFFFF2A55),
                          onPressed: _endOrDeclineCall,
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'DECLINE',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          heroTag: 'accept_fake_call',
                          backgroundColor: const Color(0xFF00C853),
                          onPressed: _acceptCall,
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ACCEPT',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    FloatingActionButton(
                      heroTag: 'hangup_fake_call',
                      backgroundColor: const Color(0xFFFF2A55),
                      onPressed: _endOrDeclineCall,
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'END CALL',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
