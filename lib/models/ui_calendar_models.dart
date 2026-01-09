import 'dart:math';

enum WorkType { basic, substitute, overtime, holiday, night, weekly }

class UICalendarAlba {
  UICalendarAlba({
    required this.id,
    required this.name,
    this.colorHex = '#3B82F6',
    this.hourlyWage = 9860,
    this.payDay = 25,
  });

  final String id;
  final String name;
  final String colorHex;
  final int hourlyWage;
  final int payDay;
}

class UICalendarSchedule {
  UICalendarSchedule({
    String? id,
    required this.albaId,
    required this.year,
    required this.month,
    required this.day,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.breakMinutes = 0,
    this.overrideHourlyWage,
    this.workType = WorkType.basic,
  }) : id = id ?? _rand();

  final String id;
  final String albaId;
  final int year, month, day;
  final int startHour, startMinute, endHour, endMinute;
  final int breakMinutes;
  final int? overrideHourlyWage;
  final WorkType workType;

  static String _rand() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
