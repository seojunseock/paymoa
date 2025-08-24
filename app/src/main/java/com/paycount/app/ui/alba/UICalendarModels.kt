package com.paycount.app.ui.alba

import java.util.UUID

data class UICalendarAlba(
    val id: String,
    val name: String,
    val colorHex: String = "#3B82F6",
    val hourlyWage: Long = 9860L,
    val payDay: Int = 25,
    // 선택(미사용 가능): 이후 확장을 위한 규칙 (날짜 문자열 2025-08-20 형태 권장)
    val wageRules: List<WageRule> = emptyList()
)

data class WageRule(
    val effectiveFrom: String,   // "YYYY-MM-DD" 로 저장
    val wage: Long
)

data class UICalendarSchedule(
    val id: String = UUID.randomUUID().toString(), // ★ 고유 ID
    val albaId: String,
    val year: Int,
    val month: Int,
    val day: Int,
    val startHour: Int,
    val startMinute: Int,
    val endHour: Int,
    val endMinute: Int,
    val breakMinutes: Int = 0,
    val overrideHourlyWage: Long? = null          // ★ 그날만 다른 시급
)
