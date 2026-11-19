import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/safety_ping.dart';
import '../services/offline_vault_service.dart';
import '../services/rescue_nav_service.dart';
import '../services/sos_alarm_service.dart';
import '../services/sos_cloud_service.dart';

class AlertGroup {
  final String name;
  final List<String> responderIds;
  bool isSelected;

  AlertGroup({
    required this.name,
    required this.responderIds,
    this.isSelected = true,
  });

  int get membersCount => responderIds.length;
}

class TacticalHomeScreen extends StatefulWidget {
  const TacticalHomeScreen({super.key});

  @override
  State<TacticalHomeScreen> createState() => _TacticalHomeScreenState();
}

class _TacticalHomeScreenState extends State<TacticalHomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitController;

  bool _isSosActive = false;
  bool _isLocating = false;
  bool _isPublishingCloud = false;
  bool _alarmAcknowledged = false;
  String? _lastTriggeredAlertKey;

  // Separate IDs: Sender (help seeker) vs Responder (helper receiving alerts)
  String _mySenderId = 'SOS-1001';
  String _myResponderId = 'RES-2001';

  String _statusText = 'SHIELD ARMED • STANDBY';
  String _locationSource = 'DEFAULT SECTOR';
  double _lat = 25.5941;
  double _lng = 85.1376;

  double? _localTargetLat;
  double? _localTargetLng;
  String _localTargetLabel = 'NO ACTIVE DISTRESS SIGNAL';
  String _lastSentSummary = '';

  final List<AlertGroup> _alertGroups = [
    AlertGroup(
      name: 'Family Shield',
      responderIds: ['RES-2001'],
      isSelected: true,
    ),
    AlertGroup(
      name: 'Trusted Circle',
      responderIds: ['RES-2002'],
      isSelected: false,
    ),
    AlertGroup(
      name: 'Local Rapid Squad',
      responderIds: ['RES-9001'],
      isSelected: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitController.dispose();
    SosAlarmService.instance.stopEmergencySiren();
    super.dispose();
  }

  void _handleIncomingAlert(LiveSosAlert alert) {
    // Never sound alarm on the device that sent this SOS
    if (alert.senderId.trim().toUpperCase() == _mySenderId.trim().toUpperCase()) {
      return;
    }

    final alertKey = '${alert.id}_${alert.timestamp.millisecondsSinceEpoch}';
    if (_lastTriggeredAlertKey == alertKey) return;
    _lastTriggeredAlertKey = alertKey;
    _alarmAcknowledged = false;
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

  List<String> _collectSelectedTargetIds() {
    final ids = <String>[];
    for (final g in _alertGroups) {
      if (g.isSelected) {
        for (final id in g.responderIds) {
          final clean = id.trim().toUpperCase();
          if (clean.isNotEmpty && !ids.contains(clean)) {
            ids.add(clean);
          }
        }
      }
    }
    return ids;
  }

  void _editCustomIdsDialog() {
    final senderController = TextEditingController(text: _mySenderId);
    final responderController = TextEditingController(text: _myResponderId);
    String? errorMsg;
    bool checking = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF131B26),
          title: const Text(
            'CUSTOM SENDER & RESPONDER IDs',
            style: TextStyle(color: Color(0xFF00F0FF), fontSize: 15),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: senderController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'My Sender ID (When YOU need help)',
                  hintText: 'e.g. SOS-GANGA-01',
                  hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                  labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: responderController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'My Responder ID (Receive others\' SOS)',
                  hintText: 'e.g. RES-GUARD-01',
                  hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                  labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMsg!,
                  style: const TextStyle(
                    color: Color(0xFFFF4D6D),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
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
              onPressed: checking
                  ? null
                  : () async {
                      final nextSender =
                          senderController.text.trim().toUpperCase();
                      final nextResponder =
                          responderController.text.trim().toUpperCase();

                      if (nextSender.isEmpty || nextResponder.isEmpty) {
                        setDialogState(() {
                          errorMsg = 'Both Sender ID and Responder ID are required.';
                        });
                        return;
                      }

                      if (nextSender == nextResponder) {
                        setDialogState(() {
                          errorMsg =
                              'Sender ID and Responder ID should be different to avoid self-alarm.';
                        });
                        return;
                      }

                      setDialogState(() {
                        checking = true;
                        errorMsg = null;
                      });

                      bool taken = false;
                      if (nextSender != _mySenderId) {
                        try {
                          taken = await SosCloudService.instance
                              .isSenderIdTaken(nextSender);
                        } catch (_) {}
                      }

                      if (taken) {
                        setDialogState(() {
                          checking = false;
                          errorMsg =
                              'Sender ID "$nextSender" already exists in cloud history. Choose a unique ID.';
                        });
                        return;
                      }

                      setState(() {
                        _mySenderId = nextSender;
                        _myResponderId = nextResponder;
                        _lastTriggeredAlertKey = null;
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: Text(checking ? 'CHECKING...' : 'SAVE UNIQUE IDs'),
            ),
          ],
        ),
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
    final selectedGroups = _alertGroups.where((g) => g.isSelected).toList();
    final targetIds = _collectSelectedTargetIds();
    final groupsSummary = selectedGroups.isEmpty
        ? 'No Group Selected'
        : selectedGroups.map((g) => g.name).join(', ');

    setState(() {
      _isSosActive = nextState;
      _statusText = _isSosActive
          ? 'SOS ACTIVE • SENDING FROM $_mySenderId'
          : 'SHIELD ARMED • STANDBY';
    });

    if (_isSosActive) {
      // Ensure sender never triggers self-alarm even if they accidentally list their own responder ID
      final safeTargets = targetIds
          .where((id) => id != _myResponderId.trim().toUpperCase())
          .toList();

      if (safeTargets.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Select a group with another Responder ID to send SOS.',
              ),
            ),
          );
        }
        return;
      }

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
          _localTargetLabel = 'OUTGOING SOS • FROM $_mySenderId ($groupsSummary)';
          _lastSentSummary = '${safeTargets.join(", ")} ($groupsSummary)';
          _isPublishingCloud = true;
        });
      }

      try {
        await SosCloudService.instance.publishSosToTargets(
          senderId: _mySenderId,
          targetIds: safeTargets,
          groupName: groupsSummary,
          latitude: _lat,
          longitude: _lng,
        );
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

  void _showAddGroupDialog() {
    final nameController = TextEditingController();
    final idsController = TextEditingController(text: 'RES-2001');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B26),
        title: const Text(
          'NEW RESPONDER GROUP',
          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Group Name (e.g. Family / Friends)',
                labelStyle: TextStyle(color: Colors.white60),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idsController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Responder IDs (comma separated)',
                hintText: 'RES-2001, RES-3005',
                hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F0FF),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final name = nameController.text.trim();
              final parsedIds = idsController.text
                  .split(',')
                  .map((e) => e.trim().toUpperCase())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList();
              if (name.isNotEmpty && parsedIds.isNotEmpty) {
                setState(() {
                  _alertGroups.add(
                    AlertGroup(
                      name: name,
                      responderIds: parsedIds,
                      isSelected: true,
                    ),
                  );
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('ADD GROUP'),
          ),
        ],
      ),
    );
  }

  Widget _build3dSosCore(int activeTargetsCount) {
    return GestureDetector(
      onLongPress: _toggleSos,
      child: SizedBox(
        width: 240,
        height: 240,
        child: AnimatedBuilder(
          animation: _orbitController,
          builder: (context, child) {
            final angle = _orbitController.value * 2 * math.pi;
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateX(1.05)
                    ..rotateZ(angle),
                  child: Container(
                    width: 224,
                    height: 224,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00F0FF).withValues(alpha: 0.55),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(0.85)
                    ..rotateZ(-angle * 1.25),
                  child: Container(
                    width: 204,
                    height: 204,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.6),
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 162,
                  height: 162,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isSosActive
                          ? [const Color(0xFFFF4D6D), const Color(0xFF800F2F)]
                          : [const Color(0xFF5C1D38), const Color(0xFF191229)],
                    ),
                    border: Border.all(
                      color: _isSosActive
                          ? Colors.white
                          : const Color(0xFFFF2A55).withValues(alpha: 0.85),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF2A55).withValues(
                          alpha: _isSosActive ? 0.8 : 0.45,
                        ),
                        blurRadius: _isSosActive ? 42 : 26,
                        spreadRadius: _isSosActive ? 8 : 3,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                        const SizedBox(height: 4),
                        Text(
                          'ALERT $activeTargetsCount RESPONDER(S)',
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
    final selectedTargetIds = _collectSelectedTargetIds();

    return Scaffold(
      backgroundColor: const Color(0xFF05080D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C121B),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, color: Color(0xFF00F0FF), size: 20),
            const SizedBox(width: 8),
            const Text(
              'AEGIS',
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
                '3D',
                style: TextStyle(
                  color: Color(0xFF64B5F6),
                  fontSize: 10,
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
                _isSosActive ? 'SOS ACTIVE' : 'SYSTEM ARMED',
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
        stream: SosCloudService.instance.watchLatestAlertForId(_myResponderId),
        builder: (context, snapshot) {
          final incomingAlert = snapshot.data;
          final bool isFromOtherSender = incomingAlert != null &&
              incomingAlert.senderId.trim().toUpperCase() !=
                  _mySenderId.trim().toUpperCase();

          if (isFromOtherSender) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleIncomingAlert(incomingAlert);
            });
          }

          final bool hasTarget = isFromOtherSender || _localTargetLat != null;
          final double targetLat = isFromOtherSender
              ? incomingAlert.latitude
              : (_localTargetLat ?? _lat);
          final double targetLng = isFromOtherSender
              ? incomingAlert.longitude
              : (_localTargetLng ?? _lng);
          final String distanceBadgeText = hasTarget
              ? _formatDistanceFromMe(targetLat, targetLng)
              : 'NO TARGET';
          final bool showActiveAlarmBanner =
              isFromOtherSender && !_alarmAcknowledged;

          final String targetLabel = isFromOtherSender
              ? 'NEED HELP • FROM ${incomingAlert.senderId} (${incomingAlert.groupName})'
              : _localTargetLabel;
          final String targetDetail = isFromOtherSender
              ? 'DISTANCE FROM YOU: $distanceBadgeText\nSTART (MY): ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}\nEND (TARGET): ${incomingAlert.latitude.toStringAsFixed(5)}, ${incomingAlert.longitude.toStringAsFixed(5)}'
              : (_localTargetLat != null
                  ? 'DISTANCE FROM YOU: $distanceBadgeText\nSTART (MY): ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}\nEND (TARGET): ${_localTargetLat!.toStringAsFixed(5)}, ${_localTargetLng!.toStringAsFixed(5)}\nSENT TO: $_lastSentSummary'
                  : 'Set your custom Sender/Responder IDs, choose groups, then HOLD SOS.');

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sender ID & Responder ID Strip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1520),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00F0FF).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'SENDER ID: $_mySenderId  •  RESPONDER ID: $_myResponderId',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF00F0FF),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _editCustomIdsDialog,
                            child: const Text(
                              'EDIT IDs',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (showActiveAlarmBanner) ...[
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
                                    'SOS FROM ${incomingAlert.senderId}!',
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

                    // 3D Orbital SOS Centerpiece
                    Center(child: _build3dSosCore(selectedTargetIds.length)),

                    const SizedBox(height: 10),

                    Text(
                      _isPublishingCloud
                          ? 'SOS ACTIVE • SENDING FROM $_mySenderId...'
                          : _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isSosActive
                            ? const Color(0xFFFF2A55)
                            : const Color(0xFF00F0FF),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        fontSize: 13,
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

                    // Targeted Responder Groups
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
                                'RESPONDER GROUPS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                  fontSize: 12,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _showAddGroupDialog,
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 16,
                                  color: Color(0xFF00F0FF),
                                ),
                                label: const Text(
                                  'ADD GROUP',
                                  style: TextStyle(
                                    color: Color(0xFF00F0FF),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ..._alertGroups.map((group) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141E2E),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: group.isSelected
                                      ? const Color(0xFF00F0FF)
                                          .withValues(alpha: 0.45)
                                      : Colors.transparent,
                                ),
                              ),
                              child: SwitchListTile(
                                dense: true,
                                activeThumbColor: const Color(0xFF00F0FF),
                                title: Text(
                                  '${group.name} (${group.membersCount} IDs)',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  'Responders: ${group.responderIds.join(", ")} • ${group.isSelected ? "ARMED" : "MUTED"}',
                                  style: TextStyle(
                                    color: group.isSelected
                                        ? const Color(0xFF00F0FF)
                                        : Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                                value: group.isSelected,
                                onChanged: (val) {
                                  setState(() => group.isSelected = val);
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Responder Screen: Need-Help Location Card + Distance Badge
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

                    // Direct Navigation to Need-Help User's Location
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
