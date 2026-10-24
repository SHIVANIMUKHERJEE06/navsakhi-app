import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_telemetry.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _patientsRef => _db.collection('patients_telemetry');
  CollectionReference get _auditRef => _db.collection('security_audit_logs');

  Stream<List<PatientTelemetry>> streamPatientTelemetries() {
    return _patientsRef.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => PatientTelemetry.fromFirestore(doc))
          .toList();
    });
  }

  Stream<QuerySnapshot> streamAuditLogs() {
    return _auditRef
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots();
  }

  Future<void> updateTelemetry(PatientTelemetry telemetry) async {
    await _patientsRef.doc(telemetry.deviceId).set(
          telemetry.toMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> triggerThresholdEvent({
    required PatientTelemetry current,
    required bool simulateExit,
    required int simulatedRssi,
  }) async {
    final newSafe = !simulateExit;
    final newAlert = simulateExit ? 'critical' : 'normal';

    // 1. Update live patient telemetry
    await _patientsRef.doc(current.deviceId).update({
      'is_safe_zone': newSafe,
      'alert_level': newAlert,
      'rssi': simulatedRssi,
      'last_seen': FieldValue.serverTimestamp(),
    });

    // 2. Append immutable security audit trail entry
    await _auditRef.add({
      'device_id': current.deviceId,
      'patient_name': current.patientName,
      'event_type': simulateExit ? 'PERIMETER_BREACH' : 'ZONE_RESTORED',
      'rssi': simulatedRssi,
      'latitude': current.latitude,
      'longitude': current.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'severity': simulateExit ? 'HIGH' : 'INFO',
    });
  }
}
