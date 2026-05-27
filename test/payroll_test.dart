// test/payroll_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:paycount/models/ui_calendar_models.dart';
import 'package:paycount/payroll/pay_calculator.dart';
import 'package:paycount/policies/policies.dart';

// ─── 공통 테스트 헬퍼 ───────────────────────────────────────────────────────

UICalendarAlba _alba({int wage = 10000}) => UICalendarAlba(
      id: 'a1',
      name: '테스트알바',
      hourlyWage: wage,
      colorHex: 'FF0000',
      payDay: 25,
    );

/// year=2025 month=5 기준 (월~일 달력)
/// 2025-05-01=목, 2025-05-04=일(일요일), 2025-05-05=월(어린이날 빨간날)
UICalendarSchedule _sch({
  required int day,
  required int startHour,
  required int startMin,
  required int endHour,
  required int endMin,
  int breakMin = 0,
  int? wage,
  WorkType workType = WorkType.basic,
}) =>
    UICalendarSchedule(
      id: 'd$day',
      albaId: 'a1',
      year: 2025,
      month: 5,
      day: day,
      startHour: startHour,
      startMinute: startMin,
      endHour: endHour,
      endMinute: endMin,
      breakMinutes: breakMin,
      workType: workType,
      overrideHourlyWage: wage,
    );

void main() {
  // ════════════════════════════════════════════════════════
  //  1. 기본 급여 계산
  // ════════════════════════════════════════════════════════
  group('기본 급여', () {
    test('4시간 근무 × 10,000원 = 40,000원', () {
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 9, startMin: 0, endHour: 13, endMin: 0),
        policy: const SurchargePolicy(),
      );
      expect(pay, 40000);
    });

    test('휴게시간 1시간 포함 9시간 근무 → 실근무 8시간', () {
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(
            day: 7,
            startHour: 9,
            startMin: 0,
            endHour: 18,
            endMin: 0,
            breakMin: 60),
        policy: const SurchargePolicy(),
      );
      expect(pay, 80000); // 8h × 10,000
    });

    test('자정 넘는 근무 (22:00~03:00 = 5시간)', () {
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 22, startMin: 0, endHour: 3, endMin: 0),
        policy: const SurchargePolicy(),
      );
      expect(pay, 50000); // 5h × 10,000
    });
  });

  // ════════════════════════════════════════════════════════
  //  2. 연장수당 (일 8시간 초과)
  // ════════════════════════════════════════════════════════
  group('연장수당 - 일 8시간 초과', () {
    const policy = SurchargePolicy(
      overtimeEnabled: true,
      overtimePercent: 50,
      overtimeRule: OvertimeRule.dailyOver8,
    );

    test('10시간 근무 → 초과 2시간에 50% 추가', () {
      // basePay = 10h × 10,000 = 100,000
      // overtime = 2h × 10,000 × 50% = 10,000
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 9, startMin: 0, endHour: 19, endMin: 0),
        policy: policy,
      );
      expect(pay, 110000);
    });

    test('8시간 정확히 → 연장 없음', () {
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 9, startMin: 0, endHour: 17, endMin: 0),
        policy: policy,
      );
      expect(pay, 80000); // 연장 없음
    });

    test('7시간 → 연장 없음', () {
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 9, startMin: 0, endHour: 16, endMin: 0),
        policy: policy,
      );
      expect(pay, 70000);
    });
  });

  // ════════════════════════════════════════════════════════
  //  3. 야간수당 (22:00~06:00)
  // ════════════════════════════════════════════════════════
  group('야간수당', () {
    const policy = SurchargePolicy(
      nightEnabled: true,
      nightPercent: 50,
    );

    test('22:00~02:00 근무 → 야간 4시간에 50% 추가', () {
      // basePay = 4h × 10,000 = 40,000
      // night = 4h × 10,000 × 50% = 20,000
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 22, startMin: 0, endHour: 2, endMin: 0),
        policy: policy,
      );
      expect(pay, 60000);
    });

    test('18:00~22:00 근무 → 야간 없음', () {
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 18, startMin: 0, endHour: 22, endMin: 0),
        policy: policy,
      );
      expect(pay, 40000); // 야간 없음
    });

    test('20:00~02:00 근무 → 야간 2시간(22:00~02:00)만 가산', () {
      // basePay = 6h × 10,000 = 60,000
      // night = 2h × 10,000 × 50% = 10,000 (22:00~24:00 구간)
      // 00:00~02:00 → nextday 00:00~06:00 구간에 겹침 = 2h 추가
      // total night = 4h × 10,000 × 50% = 20,000? 아니면 22:00~02:00 = 4h
      // _overlapMinutesWithNight: 22:00~24:00(2h) + 00:00~02:00(2h) = 4h
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 20, startMin: 0, endHour: 2, endMin: 0),
        policy: policy,
      );
      // basePay = 6h × 10,000 = 60,000
      // nightPay = 4h × 10,000 × 50% = 20,000
      expect(pay, 80000);
    });
  });

  // ════════════════════════════════════════════════════════
  //  4. 휴일수당
  // ════════════════════════════════════════════════════════
  group('휴일수당', () {
    // 2025-05-04는 일요일
    const sundayPolicy = SurchargePolicy(
      holidayEnabled: true,
      holidayPercent: 50,
      weeklyHolidayWeekday: DateTime.sunday,
    );

    test('일요일(05-04) 4시간 근무 → 50% 추가', () {
      // basePay = 4h × 10,000 = 40,000
      // holidayPay = 4h × 10,000 × 50% = 20,000
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 4, startHour: 10, startMin: 0, endHour: 14, endMin: 0),
        policy: sundayPolicy,
      );
      expect(pay, 60000);
    });

    test('평일(05-07, 수요일) 근무 → 휴일수당 없음', () {
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 7, startHour: 10, startMin: 0, endHour: 14, endMin: 0),
        policy: sundayPolicy,
      );
      expect(pay, 40000); // 휴일 없음
    });

    test('토요일(05-03)은 기본 설정에서 휴일 아님', () {
      // 토요일은 weeklyHolidayWeekday=일요일이면 해당 없음
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 3, startHour: 10, startMin: 0, endHour: 14, endMin: 0),
        policy: sundayPolicy,
      );
      expect(pay, 40000); // 토요일 = 휴일 아님
    });

    test('extraHolidayYmds로 등록한 날(05-05) → 휴일 적용', () {
      final policy = sundayPolicy.copyWith(
        extraHolidayYmds: ['2025-05-05'], // 어린이날
      );
      // 2025-05-05는 월요일이지만 extraHoliday로 등록
      // basePay = 4h × 10,000 = 40,000
      // holidayPay = 4h × 10,000 × 50% = 20,000
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 5, startHour: 10, startMin: 0, endHour: 14, endMin: 0),
        policy: policy,
      );
      expect(pay, 60000);
    });

    test('한국법 2단계: 10시간 일요일 근무 (8h이하 50%, 초과 100%)', () {
      final policy = SurchargePolicy(
        holidayEnabled: true,
        holidayPercent: 50,
        holidayUseKoreanLawTier: true,
        weeklyHolidayWeekday: DateTime.sunday,
      );
      // basePay = 10h × 10,000 = 100,000
      // holiday 8h × 50% = 40,000
      // holiday 2h × 100% = 20,000
      // total = 100,000 + 40,000 + 20,000 = 160,000
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 4, startHour: 9, startMin: 0, endHour: 19, endMin: 0),
        policy: policy,
      );
      expect(pay, 160000);
    });
  });

  // ════════════════════════════════════════════════════════
  //  5. 휴일+연장 이중계산 방지 (수정된 버그)
  // ════════════════════════════════════════════════════════
  group('휴일+연장 이중계산 방지', () {
    test('한국법 2단계 휴일 ON + 연장수당 ON → 연장수당 별도 계산 안함', () {
      final policy = SurchargePolicy(
        holidayEnabled: true,
        holidayPercent: 50,
        holidayUseKoreanLawTier: true,
        weeklyHolidayWeekday: DateTime.sunday,
        overtimeEnabled: true,
        overtimePercent: 50,
        overtimeRule: OvertimeRule.dailyOver8,
      );
      // 2025-05-04 일요일, 10시간 근무
      // basePay = 10h × 10,000 = 100,000
      // holidayPay = 8h×50% + 2h×100% = 40,000 + 20,000 = 60,000
      // overtimePay = 0 (이중계산 방지)
      // 예상: 160,000
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 4, startHour: 9, startMin: 0, endHour: 19, endMin: 0),
        policy: policy,
      );
      expect(pay, 160000);
      // 만약 이중계산이면 = 100,000 + 60,000 + 10,000 = 170,000 (틀림)
      expect(pay, isNot(170000));
    });

    test('한국법 2단계 OFF + 연장수당 ON 일요일 → 연장수당 정상 적용됨', () {
      final policy = SurchargePolicy(
        holidayEnabled: true,
        holidayPercent: 50,
        holidayUseKoreanLawTier: false, // 2단계 OFF
        weeklyHolidayWeekday: DateTime.sunday,
        overtimeEnabled: true,
        overtimePercent: 50,
        overtimeRule: OvertimeRule.dailyOver8,
      );
      // 2025-05-04 일요일, 10시간 근무
      // basePay = 10h × 10,000 = 100,000
      // holidayPay = 10h × 50% = 50,000
      // overtimePay = 2h × 50% = 10,000
      // 예상: 160,000
      final pay = computeSinglePay(
        alba: _alba(),
        s: _sch(day: 4, startHour: 9, startMin: 0, endHour: 19, endMin: 0),
        policy: policy,
      );
      expect(pay, 160000);
    });
  });

  // ════════════════════════════════════════════════════════
  //  6. day66 세금 계산 (수정된 버그)
  // ════════════════════════════════════════════════════════
  group('day66 세금', () {
    test('일당 15만원 이하 → 세금 0원', () {
      // 5h × 10,000 = 50,000 (15만원 미달)
      final s = _sch(
          day: 7,
          startHour: 9,
          startMin: 0,
          endHour: 14,
          endMin: 0,
          breakMin: 0);
      final tax = computeDay66Tax(
        alba: _alba(),
        schedules: [s],
        policy: const SurchargePolicy(),
      );
      expect(tax, 0);
    });

    test('일당 20만원 → (20만-15만) × 2.97% = 1,485원', () {
      // 시급 20,000원 × 10시간 = 200,000원
      final s = _sch(
          day: 7,
          startHour: 9,
          startMin: 0,
          endHour: 19,
          endMin: 0,
          breakMin: 0);
      final tax = computeDay66Tax(
        alba: _alba(wage: 20000),
        schedules: [s],
        policy: const SurchargePolicy(),
      );
      // taxable = 200,000 - 150,000 = 50,000
      // tax = 50,000 × 2.97% = 1,485원
      expect(tax, 1485);
    });

    test('같은 날 두 스케줄 → 합산 후 비과세 1회만 적용', () {
      // 오전 9~13시 (4h = 40,000), 오후 14~20시 (6h = 60,000)
      // 합계 10h = 100,000 → 비과세 기준(15만) 미달 → 세금 0
      final s1 = _sch(
          day: 7, startHour: 9, startMin: 0, endHour: 13, endMin: 0);
      final s2 = _sch(
          day: 7, startHour: 14, startMin: 0, endHour: 20, endMin: 0);
      final tax = computeDay66Tax(
        alba: _alba(),
        schedules: [s1, s2],
        policy: const SurchargePolicy(),
      );
      expect(tax, 0);
    });

    test('이틀 연속 근무 → 날짜별 각각 비과세 적용', () {
      // 7일: 8h × 10,000 = 80,000 → 비과세 기준 미달 → 세금 0
      // 8일: 20h? 말고 더 현실적으로 시급 20,000 × 10h = 200,000 → 세금 1,485
      final s1 = _sch(
          day: 7,
          startHour: 9,
          startMin: 0,
          endHour: 17,
          endMin: 0,
          breakMin: 0);
      final s2 = UICalendarSchedule(
        id: 'd8',
        albaId: 'a1',
        year: 2025,
        month: 5,
        day: 8,
        startHour: 9,
        startMinute: 0,
        endHour: 19,
        endMinute: 0,
        breakMinutes: 0,
      );
      final tax = computeDay66Tax(
        alba: _alba(wage: 20000),
        schedules: [s1, s2],
        policy: const SurchargePolicy(),
      );
      // 7일: 8h × 20,000 = 160,000 → taxable 10,000 → 297원
      // 8일: 10h × 20,000 = 200,000 → taxable 50,000 → 1,485원
      // 합계 = 297 + 1,485 = 1,782원
      expect(tax, 1782);
    });
  });

  // ════════════════════════════════════════════════════════
  //  7. 세금 + 보험 공제
  // ════════════════════════════════════════════════════════
  group('세금 + 보험 공제', () {
    test('세금 없음 + 보험 없음 → gross = net', () {
      final result = computeMonthlySummary(
        alba: _alba(),
        ymYear: 2025,
        ymMonth: 5,
        schedules: [
          _sch(day: 7, startHour: 9, startMin: 0, endHour: 17, endMin: 0),
        ],
        tax: TaxConfig.none,
        insurance: const InsuranceNone(),
        policy: const SurchargePolicy(),
      );
      expect(result.gross, result.net); // 공제 없음
    });

    test('3.3% 세금 + 보험 없음', () {
      final result = computeMonthlySummary(
        alba: _alba(),
        ymYear: 2025,
        ymMonth: 5,
        schedules: [
          _sch(day: 7, startHour: 9, startMin: 0, endHour: 17, endMin: 0),
        ],
        tax: TaxConfig.biz33,
        insurance: const InsuranceNone(),
        policy: const SurchargePolicy(),
      );
      // gross = 8h × 10,000 = 80,000
      // tax = 80,000 × 3.3% = 2,640
      // net = 80,000 - 2,640 = 77,360
      expect(result.gross, 80000);
      expect(result.net, 77360);
    });

    test('day66 세금: 일당 20만원(시급 20,000 × 10h) → 정확한 세액', () {
      final result = computeMonthlySummary(
        alba: _alba(wage: 20000),
        ymYear: 2025,
        ymMonth: 5,
        schedules: [
          UICalendarSchedule(
            id: 'd7',
            albaId: 'a1',
            year: 2025,
            month: 5,
            day: 7,
            startHour: 9,
            startMinute: 0,
            endHour: 19,
            endMinute: 0,
            breakMinutes: 0,
          ),
        ],
        tax: TaxConfig.day66,
        insurance: const InsuranceNone(),
        policy: const SurchargePolicy(),
      );
      // gross = 200,000
      // tax = (200,000 - 150,000) × 2.97% = 1,485
      // net = 200,000 - 1,485 = 198,515
      expect(result.gross, 200000);
      expect(result.net, 198515);
    });

    test('고용보험 0.9% 공제', () {
      final result = computeMonthlySummary(
        alba: _alba(),
        ymYear: 2025,
        ymMonth: 5,
        schedules: [
          _sch(day: 7, startHour: 9, startMin: 0, endHour: 17, endMin: 0),
        ],
        tax: TaxConfig.none,
        insurance: const InsuranceEmploymentOnly(),
        policy: const SurchargePolicy(),
      );
      // gross = 80,000, ins = 80,000 × 0.9% = 720
      // net = 80,000 - 720 = 79,280
      expect(result.net, 79280);
    });

    test('4대보험 9.4% 공제', () {
      final result = computeMonthlySummary(
        alba: _alba(),
        ymYear: 2025,
        ymMonth: 5,
        schedules: [
          _sch(day: 7, startHour: 9, startMin: 0, endHour: 17, endMin: 0),
        ],
        tax: TaxConfig.none,
        insurance: const InsuranceFour(),
        policy: const SurchargePolicy(),
      );
      // gross = 80,000, ins = 80,000 × 9.4% = 7,520
      // net = 80,000 - 7,520 = 72,480
      expect(result.net, 72480);
    });
  });

  // ════════════════════════════════════════════════════════
  //  8. 주휴수당
  // ════════════════════════════════════════════════════════
  group('주휴수당', () {
    // 2025-05-11(일)~05-17(토) 주
    // 월(12)~금(16) 각 8시간 = 주 40시간

    List<UICalendarSchedule> _fullWeek(int hourlyWage) {
      return [12, 13, 14, 15, 16].map((day) {
        return UICalendarSchedule(
          id: 'd$day',
          albaId: 'a1',
          year: 2025,
          month: 5,
          day: day,
          startHour: 9,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
          breakMinutes: 0,
        );
      }).toList();
    }

    test('주 40시간 근무 → 주휴 8시간 지급', () {
      final policy = const SurchargePolicy(weeklyHolidayEnabled: true);
      final schedules = _fullWeek(10000);
      final result = computeMonthlySummary(
        alba: _alba(),
        ymYear: 2025,
        ymMonth: 5,
        schedules: schedules,
        tax: TaxConfig.none,
        insurance: const InsuranceNone(),
        policy: policy,
      );
      // 주 5일 × 8h × 10,000 = 400,000
      // 주휴: (40/40) × 8h × 10,000 = 80,000
      // 총 gross = 480,000
      expect(result.gross, 480000);
    });

    test('주 20시간 근무 → 주휴 4시간 지급 (비례)', () {
      final policy = const SurchargePolicy(weeklyHolidayEnabled: true);
      // 월~금 각 4시간 = 주 20시간
      final schedules = [12, 13, 14, 15, 16].map((day) {
        return UICalendarSchedule(
          id: 'd$day',
          albaId: 'a1',
          year: 2025,
          month: 5,
          day: day,
          startHour: 9,
          startMinute: 0,
          endHour: 13,
          endMinute: 0,
          breakMinutes: 0,
        );
      }).toList();
      final result = computeMonthlySummary(
        alba: _alba(),
        ymYear: 2025,
        ymMonth: 5,
        schedules: schedules,
        tax: TaxConfig.none,
        insurance: const InsuranceNone(),
        policy: policy,
      );
      // 주 5일 × 4h × 10,000 = 200,000
      // 주휴: (20/40) × 8h × 10,000 = 40,000
      // 총 gross = 240,000
      expect(result.gross, 240000);
    });

    test('주 14시간 근무 → 주휴 없음 (15시간 미달)', () {
      final policy = const SurchargePolicy(weeklyHolidayEnabled: true);
      // 월~금 각 168분(2h48m) ≈ 14h/주
      final schedules = [12, 13, 14, 15, 16].map((day) {
        return UICalendarSchedule(
          id: 'd$day',
          albaId: 'a1',
          year: 2025,
          month: 5,
          day: day,
          startHour: 9,
          startMinute: 0,
          endHour: 11,
          endMinute: 48,
          breakMinutes: 0,
        );
      }).toList();
      final result = computeMonthlySummary(
        alba: _alba(),
        ymYear: 2025,
        ymMonth: 5,
        schedules: schedules,
        tax: TaxConfig.none,
        insurance: const InsuranceNone(),
        policy: policy,
      );
      // 주 5일 × 168분 = 840분 < 900분(15h) → 주휴 없음
      // gross = 5 × 168분 × (10,000/60) = 140,000
      expect(result.gross, 140000);
    });
  });
}
