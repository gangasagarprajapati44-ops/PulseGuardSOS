import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/safety_ping.dart';
import '../services/offline_vault_service.dart';
import '../services/rescue_nav_service.dart';
import '../services/sos_alarm_service.dart';
import '../services/sos_cloud_service.dart';

class ResponseGroup {
  final String name;
  final List<String> responseIds;
  bool isTicked;

  ResponseGroup({
    required this.name,
    required this.responseIds,
    this.isTicked = false,
  });

  int get idsCount => responseIds.length;
}

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
  String? _lastTriggeredAlertKey;

  // Separate IDs for each user: Sender ID vs Response ID
  String _mySenderId = 'SENDER-1';
  String _myResponseId = 'RESP-1';

  String _statusText = 'SHIELD ARMED • STANDBY';
  String _locationSource = 'DEFAULT SECTOR';
  double _lat = 25.5941;
  double _lng = 85.1376;

  double? _localTargetLat;
  double? _localTargetLng;
  String _localTargetLabel = 'NO ACTIVE DISTRESS SIGNAL';
  String _lastSentSummary = '';

  final List<ResponseGroup> _responseGroups = [
    ResponseGroup(
      name: 'User 2 Direct Response',
      responseIds: ['RESP-2'],
      isTicked: true,
    ),
    ResponseGroup(
      name: 'Family Response Squad',
      responseIds: ['RESP-3', 'RESP-4'],
      isTicked: false,
    ),
    ResponseGroup(
      name: 'Emergency Backup Circle',
      responseIds: ['RESP-9'],
      isTicked: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _dimensionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _dimensionController.dispose();
    SosAlarmService.instance.stopEmergencySiren();
    super.dispose();
  }

  void _handleIncomingAlert(LiveSosAlert alert) {
    if (alert.senderId.trim().toUpperCase() ==
        _mySenderId.trim().toUpperCase()) {
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

  List<String> _collectTickedResponseIds() {
    final ids = <String>[];
    final myRespClean = _myResponseId.trim().toUpperCase();
    for (final g in _responseGroups) {
      if (g.isTicked) {
        for (final id in g.responseIds) {
          final clean = id.trim().toUpperCase();
          if (clean.isNotEmpty &&
              clean != myRespClean &&
              !ids.contains(clean)) {
            ids.add(clean);
          }
        }
      }
    }
    return ids;
  }

  void _editIdsDialog() {
    final senderController = TextEditingController(text: _mySenderId);
    final responseController = TextEditingController(text: _myResponseId);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B26),
        title: const Text(
          'SET SENDER ID & RESPONSE ID',
          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: senderController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'My Sender ID (Your SOS Identity)',
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
                labelText: 'My Response ID (Alarm rings here when others send SOS)',
                hintText: 'e.g. RESP-1',
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
            onPressed: () {
              final nextSender = senderController.text.trim().toUpperCase();
              final nextResponse = responseController.text.trim().toUpperCase();
              setState(() {
                if (nextSender.isNotEmpty) _mySenderId = nextSender;
                if (nextResponse.isNotEmpty) _myResponseId = nextResponse;
                _lastTriggeredAlertKey = null;
              });
              Navigator.pop(ctx);
            },
            child: const Text('SAVE IDs'),
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
    final tickedGroups = _responseGroups.where((g) => g.isTicked).toList();
    final targetResponseIds = _collectTickedResponseIds();

    if (targetResponseIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please TICK at least one Response Group to send SOS alarm.',
            ),
          ),
        );
      }
      return;
    }

    final nextState = !_isSosActive;
    final groupsSummary =
        tickedGroups.map((g) => g.name).join(', ');

    setState(() {
      _isSosActive = nextState;
      _statusText = _isSosActive
          ? 'SOS ACTIVE • ALARM SENT TO ${targetResponseIds.join(", ")}'
          : 'SHIELD ARMED • STANDBY';
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
              'OUTGOING SOS FROM $_mySenderId • $groupsSummary';
          _lastSentSummary = '${targetResponseIds.join(", ")} ($groupsSummary)';
          _isPublishingCloud = true;
        });
      }

      try {
        await SosCloudService.instance.publishSosToResponseIds(
          senderId: _mySenderId,
          responseIds: targetResponseIds,
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

  void _showAddResponseGroupDialog() {
    final nameController = TextEditingController();
    final idsController = TextEditingController(text: 'RESP-2');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B26),
        title: const Text(
          'NEW RESPONSE GROUP',
          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Response Group Name',
                labelStyle: TextStyle(color: Colors.white60),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idsController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Response IDs (comma separated)',
                hintText: 'RESP-2, RESP-5',
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
                  _responseGroups.add(
                    ResponseGroup(
                      name: name,
                      responseIds: parsedIds,
                      isTicked: true,
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

  Widget _buildMultiDimensionalSosButton(int tickedTargetsCount) {
    return GestureDetector(
      onLongPress: _toggleSos,
      child: SizedBox(
        width: 260,
        height: 260,
        child: AnimatedBuilder(
          animation: _dimensionController,
          builder: (context, child) {
            final t = _dimensionController.value;
            final angle = t * 2 * math.pi;
            final pulse4d = 0.5 + 0.5 * math.sin(t * 4 * math.pi);

            return Stack(
              alignment: Alignment.center,
              children: [
                // 5D Outer Hyper-Aura Glow
                Container(
                  width: 248 + (pulse4d * 10),
                  height: 248 + (pulse4d * 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFF2A55)
                            .withValues(alpha: 0.14 + pulse4d * 0.12),
                        const Color(0xFF00F0FF).withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // 3D Gimbal Ring X/Z
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0018)
                    ..rotateX(1.1)
                    ..rotateZ(angle),
                  child: Container(
                    width: 232,
                    height: 232,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00F0FF).withValues(alpha: 0.7),
                        width: 2.2,
                      ),
                    ),
                  ),
                ),
                // 4D Counter-Gyro Ring Y/Z
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0018)
                    ..rotateY(0.95)
                    ..rotateZ(-angle * 1.35),
                  child: Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFF4D6D).withValues(alpha: 0.65),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                // 5D Core Tesseract-Style Frame
                Transform.rotate(
                  angle: angle * 0.5,
                  child: Container(
                    width: 184,
                    height: 184,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(42),
                      border: Border.all(
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                // Core SOS Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 162,
                  height: 162,
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
                          '$tickedTargetsCount TICKED ID(S)',
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
    final tickedResponseIds = _collectTickedResponseIds();

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
                '3D/4D/5D',
                style: TextStyle(
                  color: Color(0xFF64B5F6),
                  fontSize: 9.5,
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
        stream: SosCloudService.instance
            .watchIncomingAlertForMyResponseId(_myResponseId, _mySenderId),
        builder: (context, snapshot) {
          final incomingAlert = snapshot.data;
          if (incomingAlert != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleIncomingAlert(incomingAlert);
            });
          }

          final bool hasTarget = incomingAlert != null || _localTargetLat != null;
          final double targetLat = incomingAlert != null
              ? incomingAlert.latitude
              : (_localTargetLat ?? _lat);
          final double targetLng = incomingAlert != null
              ? incomingAlert.longitude
              : (_localTargetLng ?? _lng);
          final String distanceBadgeText = hasTarget
              ? _formatDistanceFromMe(targetLat, targetLng)
              : 'NO TARGET';
          final bool showActiveAlarmBanner =
              incomingAlert != null && !_alarmAcknowledged;

          final String targetLabel = incomingAlert != null
              ? 'INCOMING SOS • FROM ${incomingAlert.senderId} (${incomingAlert.groupName})'
              : _localTargetLabel;
          final String targetDetail = incomingAlert != null
              ? 'DISTANCE FROM YOU: $distanceBadgeText\nSTART (MY): ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}\nEND (TARGET): ${incomingAlert.latitude.toStringAsFixed(5)}, ${incomingAlert.longitude.toStringAsFixed(5)}'
              : (_localTargetLat != null
                  ? 'DISTANCE FROM YOU: $distanceBadgeText\nSTART (MY): ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}\nEND (TARGET): ${_localTargetLat!.toStringAsFixed(5)}, ${_localTargetLng!.toStringAsFixed(5)}\nSENT TO RESPONSE IDs: $_lastSentSummary'
                  : 'Tick Response Groups below, then HOLD SOS to trigger alarm on chosen Response IDs.');

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Separate Sender ID & Response ID Strip
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
                              'SENDER ID: $_mySenderId  |  RESPONSE ID: $_myResponseId',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF00F0FF),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _editIdsDialog,
                            child: const Text(
                              'SET IDs',
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
                                    'SOS ALARM FROM ${incomingAlert.senderId}!',
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

                    // 3D / 4D / 5D Special SOS Button
                    Center(
                      child: _buildMultiDimensionalSosButton(
                        tickedResponseIds.length,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      _isPublishingCloud
                          ? 'SOS ACTIVE • SENDING TO TICKED RESPONSE IDs...'
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

                    // Response Groups with Tick (Checkbox)
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
                                'RESPONSE GROUPS (TICK TO ALERT)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  fontSize: 12,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _showAddResponseGroupDialog,
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 16,
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
                          const SizedBox(height: 6),
                          ..._responseGroups.map((group) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141E2E),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: group.isTicked
                                      ? const Color(0xFF00F0FF)
                                          .withValues(alpha: 0.6)
                                      : Colors.transparent,
                                ),
                              ),
                              child: CheckboxListTile(
                                dense: true,
                                activeColor: const Color(0xFF00F0FF),
                                checkColor: Colors.black,
                                title: Text(
                                  '${group.name} (${group.idsCount} ID)',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  'Response IDs: ${group.responseIds.join(", ")} • ${group.isTicked ? "TICKED (WILL RING)" : "UNTICKED"}',
                                  style: TextStyle(
                                    color: group.isTicked
                                        ? const Color(0xFF00F0FF)
                                        : Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                                value: group.isTicked,
                                onChanged: (val) {
                                  setState(
                                    () => group.isTicked = val ?? false,
                                  );
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
