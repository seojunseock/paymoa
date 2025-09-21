package com.paycount.app.ui.alba

import java.util.UUID

/**
 * 알바(캘린더용) 기본 정보
 */
data class UICalendarAlba(
    val id: String,
    val name: String,
    val colorHex: String = "#3B82F6",
    val hourlyWage: Long = 9860L,
    val payDay: Int = 25,
    // 선택(미사용 가능): 이후 확장을 위한 규칙 (날짜 문자열 2025-08-20 형태 권장)
    val wageRules: List<WageRule> = emptyList()
)

/**
 * 특정 일자부터의 시급 규칙(옵션)
 */
data class WageRule(
    val effectiveFrom: String,   // "YYYY-MM-DD"
    val wage: Long
)

/**
 * 근무유형(주휴수당 계산 등에서 사용)
 * - BASIC: 기본 근무(주휴수당 대상)
 * - SUBSTITUTE: 대타
 * - OVERTIME: 연장
 * - HOLIDAY: 휴일
 * - NIGHT: 야간
 */
enum class WorkType {
    BASIC, SUBSTITUTE, OVERTIME, HOLIDAY, NIGHT
}

/**
 * 달력에 표시/집계되는 스케줄 단위
 * - overrideHourlyWage: 이미 "세후 스냅샷"을 저장(메인 액티비티 로직에서 차감 처리)
 * - workType: 주휴수당/가산 판단을 위해 명시 저장 (기본값 BASIC)
 */
data class UICalendarSchedule(
    val id: String = UUID.randomUUID().toString(), // 고유 ID
    val albaId: String,
    val year: Int,
    val month: Int,
    val day: Int,
    val startHour: Int,
    val startMinute: Int,
    val endHour: Int,
    val endMinute: Int,
    val breakMinutes: Int = 0,
    val overrideHourlyWage: Long? = null,
    val workType: WorkType = WorkType.BASIC
)
