import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
import 'firebase_options.dart';
import 'models/patient_telemetry.dart';
import 'services/firestore_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const NavSakhiApp());
}

class NavSakhiApp extends StatelessWidget {
  const NavSakhiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NavSakhi Safety Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const PatientMonitorScreen(),
    );
  }
}

class PatientMonitorScreen extends StatefulWidget {
  const PatientMonitorScreen({super.key});

  @override
  State<PatientMonitorScreen> createState() => _PatientMonitorScreenState();
}

class _PatientMonitorScreenState extends State<PatientMonitorScreen> {
  final FirestoreService _service = FirestoreService();
  double _rssiThreshold = -85.0; // Dynamic boundary cutoff

  @override
  void initState() {
    super.initState();
    _service.updateTelemetry(
      PatientTelemetry(
        id: 'BROOCH-01',
        patientName: 'Care Recipient (Unit 1)',
        deviceId: 'BROOCH-01',
        rssi: -65,
        batteryPct: 92.0,
        isSafeZone: true,
        alertLevel: AlertLevel.normal,
        lastSeen: DateTime.now(),
      ),
    );
  }

  void _triggerHardwareVibration() async {
    // Direct Android hardware vibrator call to bypass MIUI/HyperOS mute filters
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Pattern: wait 0ms, buzz 500ms, pause 150ms, buzz 500ms
      Vibration.vibrate(
        pattern: [0, 500, 150, 500],
        intensities: [0, 255, 0, 255],
      );
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  void _handlePerimeterAction(PatientTelemetry item, bool currentlySafe) async {
    final newSafe = !currentlySafe;
    // Simulate signal dropping 7 dBm lower than whatever the slider is set to
    final simulatedRssi = newSafe ? -65 : (_rssiThreshold.toInt() - 7);

    if (!newSafe) {
      _triggerHardwareVibration();
    } else {
      HapticFeedback.lightImpact();
    }

    await _service.triggerThresholdEvent(
      current: item,
      simulateExit: currentlySafe,
      simulatedRssi: simulatedRssi,
    );

    if (!newSafe && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ ALERT: Perimeter breach! RSSI dropped to $simulatedRssi dBm (Threshold: ${_rssiThreshold.toInt()} dBm)',
          ),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NavSakhi Safety Hub'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(Icons.shield, color: Colors.teal),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live Patient Stream Card
            StreamBuilder<List<PatientTelemetry>>(
              stream: _service.streamPatientTelemetries(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return const Center(child: Text('No active devices detected.'));
                }

                final item = list.first;
                // Breach if explicitly false in cloud OR if current RSSI is weaker than slider threshold
                final isBreached = (!item.isSafeZone) || (item.rssi < _rssiThreshold);

                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isBreached ? Colors.red : Colors.teal,
                      width: 2.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.patientName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Chip(
                              avatar: Icon(
                                isBreached ? Icons.warning : Icons.check_circle,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: Text(
                                isBreached ? 'BREACH DETECTED' : 'SAFE ZONE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor:
                                  isBreached ? Colors.red : Colors.green,
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _MetricItem(
                              icon: Icons.bluetooth_searching,
                              label: 'Signal (RSSI)',
                              value: '${item.rssi} dBm',
                              isAlert: item.rssi < _rssiThreshold,
                            ),
                            _MetricItem(
                              icon: Icons.battery_charging_full,
                              label: 'Battery',
                              value: '${item.batteryPct.toInt()}%',
                            ),
                            _MetricItem(
                              icon: Icons.location_on_outlined,
                              label: 'GPS Fix',
                              value:
                                  '${item.latitude.toStringAsFixed(2)}, ${item.longitude.toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _handlePerimeterAction(item, !isBreached),
                            icon: Icon(
                              isBreached
                                  ? Icons.home_outlined
                                  : Icons.directions_walk,
                            ),
                            label: Text(
                              isBreached
                                  ? 'Mark Patient Returned (Safe)'
                                  : 'Simulate Perimeter Breach',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isBreached ? Colors.teal : Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Perimeter Sensitivity Slider
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Perimeter RSSI Sensitivity',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.teal.shade300,
                            ),
                          ),
                          child: Text(
                            '${_rssiThreshold.toInt()} dBm',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _rssiThreshold,
                      min: -100.0,
                      max: -60.0,
                      divisions: 40,
                      activeColor: Colors.teal,
                      label: '${_rssiThreshold.toInt()} dBm',
                      onChanged: (val) {
                        setState(() {
                          _rssiThreshold = val;
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Far (-100 dBm)',
                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('Close (-60 dBm)',
                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Security & Audit Trail',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Live Audit Feed
            StreamBuilder<QuerySnapshot>(
              stream: _service.streamAuditLogs(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Audit Log Error: ${snapshot.error}');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No breach events recorded yet. Safe operation.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final eventType = data['event_type'] ?? 'UNKNOWN';
                    final isBreach = eventType == 'PERIMETER_BREACH';
                    final rssi = data['rssi'] ?? 0;
                    final ts = data['timestamp'] as Timestamp?;
                    final timeText = ts != null
                        ? ts.toDate().toLocal().toString().split('.')[0]
                        : 'Just now';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 1,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isBreach ? Colors.red.shade100 : Colors.green.shade100,
                          child: Icon(
                            isBreach ? Icons.notifications_active : Icons.check,
                            color: isBreach ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(
                          eventType,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isBreach ? Colors.red : Colors.green.shade900,
                          ),
                        ),
                        subtitle: Text('Recorded: $timeText (Signal: $rssi dBm)'),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isAlert;

  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: isAlert ? Colors.red : Colors.teal),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isAlert ? Colors.red : Colors.black87,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}