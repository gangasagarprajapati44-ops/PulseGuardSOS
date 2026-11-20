import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/safety_ping.dart';
import '../services/emergency_contact_service.dart';
import '../services/offline_vault_service.dart';
import '../services/rescue_nav_service.dart';
import '../services/sos_alarm_service.dart';
import '../services/sos_cloud_service.dart';
import '../services/voice_sos_service.dart';
import 'fake_call_screen.dart';

class TacticalHomeScreen extends StatefulWidget {
  const TacticalHomeScreen({super.key});

  @override
  State<TacticalHomeScreen> createState() => _TacticalHomeScreenState();
}

class _TacticalHomeScreenState extends State<TacticalHomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dimensionController;

  bool _isSosActive = false;
  bool _isLocating = false;
  bool _isPublishingCloud = false;
  bool _alarmAcknowledged = false;
  bool _voiceArmed = false;
  bool _sendSmsOnSos = true;
  String _voiceStatus = 'VOICE: STANDBY';

  String? _activeAlertId;
  Set<String> _handledAlertIds = <String>{};

  String _mySenderId = 'SENDER-1';
  String _targetResponseId = 'RESP-2';

  String _statusText = 'SHIELD ARMED • PAIR LOCKED';
  String _locationSource = 'DEFAULT SECTOR';
  double _lat = 25.5941;
  double _lng = 85.1376;

  double? _localTargetLat;
  double? _localTargetLng;
  String _localTargetLabel = 'NO ACTIVE DISTRESS SIGNAL';

  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    final saved = OfflineVaultService.getSavedIds();
    _mySenderId = _cleanCode(saved.mySenderId, 'SENDER-1');
    _targetResponseId = _cleanCode(saved.targetResponseId, 'RESP-2');
    _handledAlertIds = OfflineVaultService.getHandledAlertIds();
    _contacts = OfflineVaultService.getSavedContacts();

    _dimensionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _dimensionController.dispose();
    SosAlarmService.instance.stopEmergencySiren();
    VoiceSosService.instance.stopListening(onStatus: (_) {});
    super.dispose();
  }

  String _cleanCode(String input, String fallback) {
    final cleaned = input
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  Future<void> _toggleVoiceTrigger() async {
    if (_voiceArmed) {
      await VoiceSosService.instance.stopListening(
        onStatus: (st) {
          if (mounted) setState(() => _voiceStatus = st);
        },
      );
      if (mounted) setState(() => _voiceArmed = false);
      return;
    }

    final started = await VoiceSosService.instance.startListening(
      onStatus: (st) {
        if (mounted) setState(() => _voiceStatus = st);
      },
      onDoubleNeedHelp: () async {
        if (!_isSosActive) {
          await _toggleSos();
        }
      },
    );

    if (mounted) {
      setState(() => _voiceArmed = started);
    }
  }

  void _openFakeCall() {
    final firstContact = _contacts.firstWhere(
      (c) => c.phone.trim().isNotEmpty,
      orElse: () => EmergencyContact(
        name: 'GUARDIAN CALL',
        phone: '+91 98XXX XXXXX',
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FakeCallScreen(
          callerName: firstContact.name,
          callerNumber: firstContact.phone,
        ),
      ),
    );
  }

  void _showAddContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B26),
        title: const Text(
          'ADD EMERGENCY CONTACT',
          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Contact Name (e.g. Mom / Brother)',
                labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Mobile Number (with country code)',
                hintText: '+919876543210',
                hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F0FF),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              if (name.isNotEmpty && phone.isNotEmpty) {
                final updated = [
                  ..._contacts,
                  EmergencyContact(name: name, phone: phone, enabled: true),
                ];
                await OfflineVaultService.saveContacts(updated);
                if (mounted) setState(() => _contacts = updated);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleIncomingAlert(LiveSosAlert alert) async {
    if (!alert.isVerifiedPair) return;
    if (alert.senderId.trim().toUpperCase() ==
        _mySenderId.trim().toUpperCase()) {
      return;
    }

    if (_handledAlertIds.contains(alert.id)) {
      return;
    }

    _handledAlertIds.add(alert.id);
    await OfflineVaultService.markAlertHandled(alert.id);

    if (!mounted) return;
    setState(() {
      _activeAlertId = alert.id;
      _alarmAcknowledged = false;
    });
    SosAlarmService.instance.startEmergencySiren();
  }

  String _formatDistanceFromMe(double targetLat, double targetLng) {
    final meters = Geolocator.distanceBetween(
      _lat,
      _lng,
      targetLat,
      targetLng,
    );
    if (meters < 1000) {
      return '${meters.round()} m AWAY';
    }
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(2)} km AWAY';
  }

  void _editTwoIdsDialog() {
    final senderController = TextEditingController(text: _mySenderId);
    final responseController = TextEditingController(text: _targetResponseId);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B26),
        title: const Text(
          'EDIT SENDER & RESPONSE ID',
          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: senderController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'My Sender ID (A-Z, 0-9, -, _)',
                hintText: 'e.g. SENDER-1',
                hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: responseController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Target Response ID (Alarm rings on this ID)',
                hintText: 'e.g. RESP-2',
                hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F0FF),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final finalSender =
                  _cleanCode(senderController.text, _mySenderId);
              final finalResponse =
                  _cleanCode(responseController.text, _targetResponseId);

              await OfflineVaultService.saveIds(
                mySenderId: finalSender,
                targetResponseId: finalResponse,
              );

              if (!mounted) return;
              setState(() {
                _mySenderId = finalSender;
                _targetResponseId = finalResponse;
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncLiveCoordinates() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationSource = kIsWeb ? 'WEB GPS LOCKED' : 'DEVICE GPS LOCKED';
      } else {
        _locationSource = 'PERMISSION DENIED (FALLBACK)';
      }
    } catch (_) {
      _locationSource = 'OFFLINE / FALLBACK COORDS';
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _toggleSos() async {
    final nextState = !_isSosActive;

    setState(() {
      _isSosActive = nextState;
      _statusText = _isSosActive
          ? 'SOS ACTIVE • LOCKED ALERT TO $_targetResponseId'
          : 'SHIELD ARMED • PAIR LOCKED';
    });

    if (_isSosActive) {
      await _syncLiveCoordinates();

      final ping = SafetyPing(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        latitude: _lat,
        longitude: _lng,
        timestamp: DateTime.now(),
        isSos: true,
      );
      await OfflineVaultService.savePing(ping);

      if (mounted) {
        setState(() {
          _localTargetLat = _lat;
          _localTargetLng = _lng;
          _localTargetLabel =
              'LOCKED SOS FROM $_mySenderId → $_targetResponseId';
          _isPublishingCloud = true;
        });
      }

      try {
        await SosCloudService.instance.sendSosToTarget(
          senderId: _mySenderId,
          targetResponseId: _targetResponseId,
          latitude: _lat,
          longitude: _lng,
        );

        if (_sendSmsOnSos && _contacts.any((c) => c.enabled)) {
          await EmergencyContactService.instance.openSmsToContacts(
            contacts: _contacts,
            senderId: _mySenderId,
            lat: _lat,
            lng: _lng,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cloud SOS sync failed: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isPublishingCloud = false);
        }
      }
    }
  }

  Widget _buildMultiDimensionalSosButton() {
    return GestureDetector(
      onLongPress: _toggleSos,
      child: SizedBox(
        width: 264,
        height: 264,
        child: AnimatedBuilder(
          animation: _dimensionController,
          builder: (context, child) {
            final t = _dimensionController.value;
            final angle = t * 2 * math.pi;
            final pulse4d = 0.5 + 0.5 * math.sin(t * 4 * math.pi);

            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 250 + (pulse4d * 10),
                  height: 250 + (pulse4d * 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFF2A55)
                            .withValues(alpha: 0.16 + pulse4d * 0.12),
                        const Color(0xFF00F0FF).withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0018)
                    ..rotateX(1.1)
                    ..rotateZ(angle),
                  child: Container(
                    width: 234,
                    height: 234,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00F0FF).withValues(alpha: 0.72),
                        width: 2.2,
                      ),
                    ),
                  ),
                ),
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0018)
                    ..rotateY(0.95)
                    ..rotateZ(-angle * 1.35),
                  child: Container(
                    width: 212,
                    height: 212,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFF4D6D).withValues(alpha: 0.68),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: angle * 0.5,
                  child: Container(
                    width: 186,
                    height: 186,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(44),
                      border: Border.all(
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.58),
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 164,
                  height: 164,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isSosActive
                          ? [const Color(0xFFFF5C7A), const Color(0xFF7A0926)]
                          : [const Color(0xFF7A1534), const Color(0xFF140D22)],
                    ),
                    border: Border.all(
                      color: _isSosActive
                          ? Colors.white
                          : const Color(0xFFFF2A55),
                      width: 3.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF2A55).withValues(
                          alpha: _isSosActive ? 0.85 : 0.5,
                        ),
                        blurRadius: _isSosActive ? 46 : 28,
                        spreadRadius: _isSosActive ? 9 : 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '3D•4D•5D',
                          style: TextStyle(
                            color: Color(0xFF00F0FF),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isSosActive ? 'HOLD\nDISARM' : 'HOLD\nSOS',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'TO $_targetResponseId',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pings = OfflineVaultService.getAllPings();

    return Scaffold(
      backgroundColor: const Color(0xFF05080D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C121B),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFF00F0FF), size: 19),
            const SizedBox(width: 8),
            const Text(
              'PULSE GUARD SOS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF42A5F5)),
              ),
              child: const Text(
                'SECURED',
                style: TextStyle(
                  color: Color(0xFF64B5F6),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0D2822),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1DE9B6)),
              ),
              child: Text(
                _isSosActive ? 'SOS ACTIVE' : 'SHIELD LOCKED',
                style: const TextStyle(
                  color: Color(0xFF64FFDA),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<LiveSosAlert?>(
        stream: SosCloudService.instance.watchIncomingAlert(
          myListenId: _mySenderId,
          mySenderId: _mySenderId,
        ),
        builder: (context, snapshot) {
          final incomingAlert = snapshot.data;
          if (incomingAlert != null &&
              incomingAlert.isVerifiedPair &&
              !_handledAlertIds.contains(incomingAlert.id)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleIncomingAlert(incomingAlert);
            });
          }

          final bool hasUnmutedLiveAlert = incomingAlert != null &&
              incomingAlert.isVerifiedPair &&
              incomingAlert.id == _activeAlertId &&
              !_alarmAcknowledged;
          final bool hasTarget = hasUnmutedLiveAlert || _localTargetLat != null;
          final double targetLat = hasUnmutedLiveAlert
              ? incomingAlert.latitude
              : (_localTargetLat ?? _lat);
          final double targetLng = hasUnmutedLiveAlert
              ? incomingAlert.longitude
              : (_localTargetLng ?? _lng);
          final String distanceBadgeText = hasTarget
              ? _formatDistanceFromMe(targetLat, targetLng)
              : 'NO TARGET';

          final String targetLabel = hasUnmutedLiveAlert
              ? 'VERIFIED SOS • FROM ${incomingAlert.senderId}'
              : _localTargetLabel;
          final String targetDetail = hasUnmutedLiveAlert
              ? 'DISTANCE FROM YOU: $distanceBadgeText\nSTART (MY): ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}\nEND (TARGET): ${incomingAlert.latitude.toStringAsFixed(5)}, ${incomingAlert.longitude.toStringAsFixed(5)}'
              : (_localTargetLat != null
                  ? 'DISTANCE FROM YOU: $distanceBadgeText\nSTART (MY): ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}\nEND (TARGET): ${_localTargetLat!.toStringAsFixed(5)}, ${_localTargetLng!.toStringAsFixed(5)}'
                  : 'Encrypted pair shield active. HOLD SOS to alert $_targetResponseId.');

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // IDs Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1520),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF00F0FF).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SENDER ID: $_mySenderId',
                                  style: const TextStyle(
                                    color: Color(0xFF00F0FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'RESPONSE ID: $_targetResponseId',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF172232),
                              foregroundColor: const Color(0xFF00F0FF),
                              side: const BorderSide(color: Color(0xFF00F0FF)),
                            ),
                            onPressed: _editTwoIdsDialog,
                            child: const Text(
                              'EDIT IDs',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Quick Tactical Actions: Fake Call & Voice "need help" x2
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF00F0FF),
                              side: const BorderSide(color: Color(0xFF00F0FF)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _openFakeCall,
                            icon: const Icon(Icons.phone_callback, size: 18),
                            label: const Text(
                              'FAKE CALL',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _voiceArmed
                                  ? const Color(0xFF64FFDA)
                                  : Colors.white,
                              side: BorderSide(
                                color: _voiceArmed
                                    ? const Color(0xFF64FFDA)
                                    : Colors.white24,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _toggleVoiceTrigger,
                            icon: Icon(
                              _voiceArmed ? Icons.mic : Icons.mic_none,
                              size: 18,
                            ),
                            label: Text(
                              _voiceArmed ? 'VOICE ON (x2)' : 'VOICE "NEED HELP"',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),
                    Text(
                      _voiceStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (hasUnmutedLiveAlert) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A0815),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFF2A55),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.campaign,
                              color: Color(0xFFFF2A55),
                              size: 30,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'VERIFIED SOS FROM ${incomingAlert.senderId}!',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '$distanceBadgeText • ${incomingAlert.latitude.toStringAsFixed(5)}, ${incomingAlert.longitude.toStringAsFixed(5)}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                SosAlarmService.instance.stopEmergencySiren();
                                setState(() {
                                  _alarmAcknowledged = true;
                                });
                              },
                              child: const Text(
                                'STOP SIREN',
                                style: TextStyle(
                                  color: Color(0xFF00F0FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    Center(child: _buildMultiDimensionalSosButton()),

                    const SizedBox(height: 10),

                    Text(
                      _isPublishingCloud
                          ? 'SOS ACTIVE • ENCRYPTING & SENDING TO $_targetResponseId...'
                          : _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isSosActive
                            ? const Color(0xFFFF2A55)
                            : const Color(0xFF00F0FF),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        fontSize: 12.5,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Telemetry Bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1520),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text(
                                'GPS COORDS',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_lat.toStringAsFixed(3)}, ${_lng.toStringAsFixed(3)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text(
                                'SYNC MODE',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _locationSource,
                                style: const TextStyle(
                                  color: Color(0xFF00F0FF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text(
                                'VAULT PINGS',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${pings.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _isLocating ? null : _syncLiveCoordinates,
                        icon: Icon(
                          _isLocating
                              ? Icons.sync
                              : Icons.my_location_outlined,
                          size: 15,
                          color: const Color(0xFF00F0FF),
                        ),
                        label: Text(
                          _isLocating ? 'LOCKING GPS...' : 'SYNC LIVE GPS',
                          style: const TextStyle(
                            color: Color(0xFF00F0FF),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Emergency Contacts Section (Message + Live Location on SOS)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1520),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'EMERGENCY CONTACTS (SMS + GPS)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _showAddContactDialog,
                                icon: const Icon(
                                  Icons.person_add_alt_1,
                                  size: 15,
                                  color: Color(0xFF00F0FF),
                                ),
                                label: const Text(
                                  'ADD',
                                  style: TextStyle(
                                    color: Color(0xFF00F0FF),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SwitchListTile(
                            dense: true,
                            activeThumbColor: const Color(0xFF00F0FF),
                            title: const Text(
                              'Prepare Location SMS on SOS',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            value: _sendSmsOnSos,
                            onChanged: (v) => setState(() => _sendSmsOnSos = v),
                          ),
                          if (_contacts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'No emergency numbers added yet. Tap ADD to save numbers.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            ..._contacts.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final c = entry.value;
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141E2E),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  dense: true,
                                  title: Text(
                                    c.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    c.phone,
                                    style: const TextStyle(
                                      color: Color(0xFF00F0FF),
                                      fontSize: 11,
                                    ),
                                  ),
                                  trailing: Switch(
                                    activeThumbColor: const Color(0xFF00F0FF),
                                    value: c.enabled,
                                    onChanged: (val) async {
                                      final copy = List<EmergencyContact>.from(
                                        _contacts,
                                      );
                                      copy[idx] = EmergencyContact(
                                        name: c.name,
                                        phone: c.phone,
                                        enabled: val,
                                      );
                                      await OfflineVaultService.saveContacts(
                                        copy,
                                      );
                                      if (mounted) {
                                        setState(() => _contacts = copy);
                                      }
                                    },
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Need-Help Location & Distance Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121A26),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: hasTarget
                              ? const Color(0xFFFF2A55).withValues(alpha: 0.75)
                              : Colors.white12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person_pin_circle_outlined,
                                color: hasTarget
                                    ? const Color(0xFFFF2A55)
                                    : const Color(0xFF00F0FF),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'RESPONDER SCREEN • NEED-HELP LOCATION',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              if (hasTarget)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF2A55)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFFF2A55),
                                    ),
                                  ),
                                  child: Text(
                                    distanceBadgeText,
                                    style: const TextStyle(
                                      color: Color(0xFFFF6B88),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            targetLabel,
                            style: TextStyle(
                              color: hasTarget
                                  ? const Color(0xFFFF2A55)
                                  : Colors.white54,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            targetDetail,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F0FF),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final opened =
                              await RescueNavService.navigateToTargetLocation(
                            targetLat,
                            targetLng,
                            originLat: _lat,
                            originLng: _lng,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Unable to open target navigation link',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.navigation_outlined),
                        label: const Text(
                          'NAVIGATE TO TARGET LOCATION',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

