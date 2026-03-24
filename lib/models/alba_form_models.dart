import '../policies/policies.dart' as pol;
import '../payroll/payroll.dart';

/// ✅ 매장 기본 스냅샷(상속 토글에 필요)
import 'policy_history.dart';

class AlbaStoreDefaultsSnapshot {
  final int hourlyWage;
  final pol.TaxConfig tax;
  final pol.InsuranceConfig insurance;
  final pol.SurchargePolicy? surcharge;
  final PayrollPolicy payrollPolicy;
  final int payDay;
  final PolicyHistory? policyHistory; // ✅ 정책 변경 이력

  AlbaStoreDefaultsSnapshot({
    required this.hourlyWage,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.payrollPolicy,
    required this.payDay,
    this.policyHistory,
  });

  /// ✅ 날짜별 가산정책 반환
  pol.SurchargePolicy? surchargeAt(DateTime date) {
    if (policyHistory == null || policyHistory!.isEmpty) return surcharge;
    return policyHistory!.surchargeAt(date) ?? surcharge;
  }
}

class AlbaFormInitial {
  final String storeId;

  /// ✅ 신규 조인 시 알바생 본인 이름 (null이면 수정 모드)
  final String? workerName;

  final String storeName;
  final int hourlyWage;
  final pol.TaxConfig tax;
  final pol.InsuranceConfig insurance;
  final pol.SurchargePolicy? surcharge;
  final PayrollPolicy? payrollPolicy;

  final int startHour24;
  final int startMinute;
  final int endHour24;
  final int endMinute;
  final int breakMinutes;
  final Set<DateTime> selectedDates;
  final String colorHex;
  final int payDay;

  /// ✅ 상속 토글 값
  final bool inheritFromStore;

  /// ✅ 매장 기본 스냅샷(상속 ON일 때 보여주기/복귀용)
  final AlbaStoreDefaultsSnapshot? storeDefaults;

  AlbaFormInitial({
    required this.storeId,
    this.workerName,
    required this.storeName,
    required this.hourlyWage,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.startHour24,
    required this.startMinute,
    required this.endHour24,
    required this.endMinute,
    required this.breakMinutes,
    required this.selectedDates,
    required this.colorHex,
    required this.payDay,
    this.payrollPolicy,
    required this.inheritFromStore,
    this.storeDefaults,
  });
}

class AlbaFormResult {
  final String storeId;
  final bool inheritFromStore;

  /// ✅ 신규 조인 시 알바생 이름
  final String? workerName;

  final String storeName;
  final int hourlyWage;
  final pol.TaxConfig tax;
  final pol.InsuranceConfig ins;
  final pol.SurchargePolicy? surcharge;

  final PayrollPolicy payrollPolicy;

  final int startHour24;
  final int startMinute;
  final int endHour24;
  final int endMinute;
  final int breakMinutes;
  final Set<DateTime> selectedDates;
  final String colorHex;
  final int payDay;

  /// 시급 적용 시작일 (null이면 즉시 전체 적용)
  final DateTime? wageEffectiveFrom;

  /// 오늘 하루만 적용 여부 (true면 오늘만, wageEffectiveFrom은 오늘)
  final bool wageOnlyToday;

  /// 세금·보험 적용 시작일 (null이면 즉시)
  final DateTime? policyEffectiveFrom;

  /// 가산정책 적용 시작일 - 오늘 즉시 (세금보험과 날짜 다를 때 분리)
  final DateTime? surchargeEffectiveFrom;

  AlbaFormResult({
    required this.storeId,
    required this.inheritFromStore,
    this.workerName,
    required this.storeName,
    required this.hourlyWage,
    required this.tax,
    required this.ins,
    required this.surcharge,
    required this.payrollPolicy,
    required this.startHour24,
    required this.startMinute,
    required this.endHour24,
    required this.endMinute,
    required this.breakMinutes,
    required this.selectedDates,
    required this.colorHex,
    required this.payDay,
    this.wageEffectiveFrom,
    this.wageOnlyToday = false,
    this.policyEffectiveFrom,
    this.surchargeEffectiveFrom,
  });
}
