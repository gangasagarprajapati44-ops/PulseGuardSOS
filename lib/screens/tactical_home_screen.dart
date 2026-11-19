import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/safety_ping.dart';
import '../services/offline_vault_service.dart';
import '../services/rescue_nav_service.dart';
import '../services/sos_cloud_service.dart';

class AlertGroup {
  final String name;
  final int members;
  bool isSelected;

  AlertGroup({
    required this.name,
    required this.members,
    this.isSelected = true,
  });
}

class TacticalHomeScreen extends StatefulWidget {
  const TacticalHomeScreen({super.key});

  @override
  State<TacticalHomeScreen> createState() => _TacticalHomeScreenState();
}

class _TacticalHomeScreenState extends State<TacticalHomeScreen> {
  bool _isSosActive = false;
  bool _isLocating = false;
  bool _isPublishingCloud = false;
  String _statusText = 'SHIELD ARMED • STANDBY';
  String _locationSource = 'DEFAULT SECTOR';
  double _lat = 25.5941;
  double _lng = 85.1376;

  // Fallback local target location if cloud stream has no alert yet
  double? _localTargetLat;
  double? _localTargetLng;
  String _localTargetLabel = 'NO ACTIVE DISTRESS SIGNAL';
  String _localTargetGroupsSummary = '';

  final List<AlertGroup> _alertGroups = [
    AlertGroup(name: 'Family Shield', members: 4, isSelected: true),
    AlertGroup(name: 'Trusted Circle', members: 3, isSelected: true),
    AlertGroup(name: 'Local Rapid Squad', members: 5, isSelected: false),
  ];

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
    final activeGroups = _alertGroups
        .where((g) => g.isSelected)
        .map((g) => g.name)
        .toList();
    final groupsSummary =
        activeGroups.isEmpty ? 'All Responders' : activeGroups.join(', ');

    setState(() {
      _isSosActive = nextState;
      _statusText = _isSosActive
          ? 'SOS ACTIVE • SENDING LIVE LOCATION'
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
          _localTargetLabel = 'NEED HELP USER • AUTO LOCATION SHARED';
          _localTargetGroupsSummary = groupsSummary;
          _isPublishingCloud = true;
        });
      }

      try {
        await SosCloudService.instance.publishSosAlert(
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
    final membersController = TextEditingController(text: '2');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B26),
        title: const Text(
          'NEW ALERT GROUP',
          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Group Name (e.g. Hostel Friends)',
                labelStyle: TextStyle(color: Colors.white60),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: membersController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Members Count',
                labelStyle: TextStyle(color: Colors.white60),
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
              final count = int.tryParse(membersController.text.trim()) ?? 1;
              if (name.isNotEmpty) {
                setState(() {
                  _alertGroups.add(
                    AlertGroup(name: name, members: count, isSelected: true),
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

  @override
  Widget build(BuildContext context) {
    final pings = OfflineVaultService.getAllPings();

    return Scaffold(
      backgroundColor: const Color(0xFF070A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111822),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security, color: Color(0xFF00F0FF), size: 20),
            const SizedBox(width: 8),
            const Text(
              'AEGIS 3D',
              style: TextStyle(
                color: Color(0xFF00F0FF),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.6,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00F0FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF00F0FF).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                kIsWeb ? 'WEB PORTAL' : 'MOBILE APP',
                style: const TextStyle(
                  color: Color(0xFF00F0FF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<LiveSosAlert?>(
        stream: SosCloudService.instance.watchLatestAlert(),
        builder: (context, snapshot) {
          final cloudAlert = snapshot.data;
          final bool hasTarget = cloudAlert != null || _localTargetLat != null;
          final double targetLat = cloudAlert?.latitude ?? (_localTargetLat ?? _lat);
          final double targetLng = cloudAlert?.longitude ?? (_localTargetLng ?? _lng);
          final String targetLabel = cloudAlert != null
              ? 'LIVE CLOUD DISTRESS • ${cloudAlert.groupName}'
              : _localTargetLabel;
          final String targetDetail = cloudAlert != null
              ? 'TARGET: ${cloudAlert.latitude.toStringAsFixed(5)}, ${cloudAlert.longitude.toStringAsFixed(5)} • SENT TO: ${cloudAlert.groupName}'
              : (_localTargetLat != null
                  ? 'TARGET: ${_localTargetLat!.toStringAsFixed(5)}, ${_localTargetLng!.toStringAsFixed(5)} • SENT TO: $_localTargetGroupsSummary'
                  : 'HOLD SOS to auto-share & display exact target coordinates here.');

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. User Status & Own Coordinates
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B26),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isSosActive
                              ? const Color(0xFFFF2A55)
                              : const Color(0xFF00F0FF).withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _isPublishingCloud
                                ? 'SOS ACTIVE • SYNCING TO FIREBASE...'
                                : _statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _isSosActive
                                  ? const Color(0xFFFF2A55)
                                  : const Color(0xFF00F0FF),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'MY COORDS: ${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)} • $_locationSource',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'VAULT PINGS: ${pings.length}',
                                  style: const TextStyle(
                                    color: Color(0xFF00F0FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed:
                                    _isLocating ? null : _syncLiveCoordinates,
                                icon: Icon(
                                  _isLocating
                                      ? Icons.sync
                                      : Icons.my_location_outlined,
                                  size: 16,
                                  color: const Color(0xFF00F0FF),
                                ),
                                label: Text(
                                  _isLocating ? 'LOCKING...' : 'SYNC GPS',
                                  style: const TextStyle(
                                    color: Color(0xFF00F0FF),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2. Responder Screen: Need-Help User Location Card (Real-time Cloud)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141C29),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: hasTarget
                              ? const Color(0xFFFF2A55).withValues(alpha: 0.7)
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
                              const Text(
                                'RESPONDER SCREEN • NEED-HELP LOCATION',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.8,
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

                    const SizedBox(height: 22),

                    // 3. SOS Trigger Button
                    Center(
                      child: GestureDetector(
                        onLongPress: _toggleSos,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isSosActive
                                ? const Color(0xFFFF2A55)
                                : const Color(0xFF162231),
                            border: Border.all(
                              color: _isSosActive
                                  ? Colors.white
                                  : const Color(0xFFFF2A55),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF2A55).withValues(
                                  alpha: _isSosActive ? 0.75 : 0.4,
                                ),
                                blurRadius: _isSosActive ? 40 : 25,
                                spreadRadius: _isSosActive ? 8 : 4,
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
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'PRESS & HOLD 1.5s',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // 4. Alert Groups Section
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111822),
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
                                'ALERT GROUPS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  fontSize: 13,
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
                                  'ADD',
                                  style: TextStyle(
                                    color: Color(0xFF00F0FF),
                                    fontSize: 12,
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
                                color: const Color(0xFF172130),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: group.isSelected
                                      ? const Color(0xFF00F0FF)
                                          .withValues(alpha: 0.5)
                                      : Colors.transparent,
                                ),
                              ),
                              child: SwitchListTile(
                                dense: true,
                                activeThumbColor: const Color(0xFF00F0FF),
                                title: Text(
                                  group.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  '${group.members} responders • ${group.isSelected ? "ARMED" : "MUTED"}',
                                  style: TextStyle(
                                    color: group.isSelected
                                        ? const Color(0xFF00F0FF)
                                        : Colors.white54,
                                    fontSize: 11,
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

                    const SizedBox(height: 18),

                    // 5. Direct Navigation to Need-Help User's Location
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
