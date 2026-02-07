import '../policies/policies.dart' as pol;
import '../payroll/payroll.dart';

/// ✅ 매장 기본 스냅샷(상속 토글에 필요)
class AlbaStoreDefaultsSnapshot {
  final int hourlyWage;
  final pol.TaxConfig tax;
  final pol.InsuranceConfig insurance;
  final pol.SurchargePolicy? surcharge;
  final PayrollPolicy payrollPolicy;
  final int payDay;

  const AlbaStoreDefaultsSnapshot({
    required this.hourlyWage,
    required this.tax,
    required this.insurance,
    required this.surcharge,
    required this.payrollPolicy,
    required this.payDay,
  });
}

class AlbaFormInitial {
  final String storeId;

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
  final DateTime? wageEffectiveFrom;

  AlbaFormResult({
    required this.storeId,
    required this.inheritFromStore,
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
  });
}
