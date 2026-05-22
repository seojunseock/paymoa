// lib/models/store_schedule.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class StoreSchedule {
  final String id;
  final String workerUid;

  final int year;
  final int month;
  final int day;

  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final int breakMinutes;

  final String workType;
  final int? overrideHourlyWage; // ✅ 날짜별 시급 override
  final double wageMultiplier;   // ✅ 보너스 배율 (기본 1.0)

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StoreSchedule({
    required this.id,
    required this.workerUid,
    required this.year,
    required this.month,
    required this.day,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.breakMinutes,
    required this.workType,
    this.overrideHourlyWage,
    this.wageMultiplier = 1.0,
    this.createdAt,
    this.updatedAt,
  });

  String get ymd =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  factory StoreSchedule.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime? _toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return StoreSchedule(
      id: doc.id,
      workerUid: (data['workerUid'] ?? '') as String,
      year: (data['year'] as num?)?.toInt() ?? 0,
      month: (data['month'] as num?)?.toInt() ?? 0,
      day: (data['day'] as num?)?.toInt() ?? 0,
      startHour: (data['startHour'] as num?)?.toInt() ?? 0,
      startMinute: (data['startMinute'] as num?)?.toInt() ?? 0,
      endHour: (data['endHour'] as num?)?.toInt() ?? 0,
      endMinute: (data['endMinute'] as num?)?.toInt() ?? 0,
      breakMinutes: (data['breakMinutes'] as num?)?.toInt() ?? 0,
      workType: (data['workType'] ?? 'basic') as String,
      overrideHourlyWage: (data['overrideHourlyWage'] as num?)?.toInt(),
      wageMultiplier: (data['wageMultiplier'] as num?)?.toDouble() ?? 1.0,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'workerUid': workerUid,
        'ymd': ymd,
        'year': year,
        'month': month,
        'day': day,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'breakMinutes': breakMinutes,
        'workType': workType,
      };
}
