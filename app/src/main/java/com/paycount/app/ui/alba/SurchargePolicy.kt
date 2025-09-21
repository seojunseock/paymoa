package com.paycount.app.ui.alba

/** 폼/달력에서 공통으로 쓰는 가산정책 모델 – 여기 단일 정의 */
data class SurchargePolicy(
    val weeklyHolidayEnabled: Boolean = false,  // 주휴수당
    val overtimeEnabled: Boolean = false,       // 연장
    val overtimePercent: Double = 0.0,
    val holidayEnabled: Boolean = false,        // 휴일
    val holidayPercent: Double = 0.0,
    val nightEnabled: Boolean = false,          // 야간(22:00~06:00)
    val nightPercent: Double = 0.0
)
