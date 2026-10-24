import 'package:cloud_firestore/cloud_firestore.dart';

enum AlertLevel { normal, warning, critical }

class PatientTelemetry {
  final String id;
  final String patientName;
  final String deviceId;
  final int rssi;
  final double batteryPct;
  final bool isSafeZone;
  final AlertLevel alertLevel;
  final double latitude;
  final double longitude;
  final DateTime lastSeen;

  PatientTelemetry({
    required this.id,
    required this.patientName,
    required this.deviceId,
    required this.rssi,
    required this.batteryPct,
    required this.isSafeZone,
    required this.alertLevel,
    this.latitude = 16.5062,
    this.longitude = 80.6480,
    required this.lastSeen,
  });

  factory PatientTelemetry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    AlertLevel parseAlert(String? level) {
      switch (level) {
        case 'critical':
          return AlertLevel.critical;
        case 'warning':
          return AlertLevel.warning;
        default:
          return AlertLevel.normal;
      }
    }

    return PatientTelemetry(
      id: doc.id,
      patientName: data['patient_name'] ?? 'Care Recipient (Unit 1)',
      deviceId: data['device_id'] ?? 'BROOCH-01',
      rssi: (data['rssi'] ?? -68) as int,
      batteryPct: ((data['battery_pct'] ?? 88) as num).toDouble(),
      isSafeZone: (data['is_safe_zone'] ?? true) as bool,
      alertLevel: parseAlert(data['alert_level'] as String?),
      latitude: ((data['latitude'] ?? 16.5062) as num).toDouble(),
      longitude: ((data['longitude'] ?? 80.6480) as num).toDouble(),
      lastSeen: (data['last_seen'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'patient_name': patientName,
      'device_id': deviceId,
      'rssi': rssi,
      'battery_pct': batteryPct,
      'is_safe_zone': isSafeZone,
      'alert_level': alertLevel.name,
      'latitude': latitude,
      'longitude': longitude,
      'last_seen': FieldValue.serverTimestamp(),
    };
  }
}