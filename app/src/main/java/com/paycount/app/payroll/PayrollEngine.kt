package com.paycount.app.payroll

import com.paycount.app.ui.alba.*
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.roundToLong

/* ===================== 계산 결과 모델 ===================== */

data class PayBreakdown(
    val paidMinutes: Int,          // 유급 분 (휴게 제외, 자정 넘김 처리)
    val nightMinutes: Int,         // 야간(22~06) 분
    val basePay: Long,             // 기본급
    val overtimeAdd: Long,         // 연장 가산
    val holidayAdd: Long,          // 휴일 가산
    val nightAdd: Long,            // 야간 가산
    val weeklyHolidayAdd: Long,    // (시프트 단위에선 0, 월합계에서 채워짐)
    val gross: Long,               // 총지급(가산 포함, 공제 전)
    val insurance: Long,           // 4대보험/고용보험 공제
    val tax: Long,                 // 세금 공제(3.3/6.6/직접%)
    val net: Long                  // 실수령(= gross - 보험 - 세금)
)

data class MonthlySummary(
    val basePay: Long,
    val overtimeAdd: Long,
    val holidayAdd: Long,
    val nightAdd: Long,
    val weeklyHolidayAdd: Long,
    val gross: Long,
    val insurance: Long,
    val tax: Long,
    val net: Long,
    val totalPaidMinutes: Int,
    val totalNightMinutes: Int
)

/* ===================== 외부에서 부르는 진입점 ===================== */

/** 단일 스케줄(해당 근무만) 계산 */
fun computeShiftPay(
    alba: UICalendarAlba,
    schedule: UICalendarSchedule,
    tax: TaxConfig,
    insurance: InsuranceConfig,
    policy: SurchargePolicy
): PayBreakdown {
    val wage = (schedule.overrideHourlyWage ?: alba.hourlyWage).toDouble()

    val paidMin = paidMinutes(schedule.startHour, schedule.startMinute, schedule.endHour, schedule.endMinute, schedule.breakMinutes)
    val nightMin = if (policy.nightEnabled) nightMinutes(
        schedule.startHour, schedule.startMinute, schedule.endHour, schedule.endMinute
    ) else 0

    val paidHours = paidMin / 60.0
    val nightHours = nightMin / 60.0

    val base = (wage * paidHours).roundToLong()

    val overtimeAdd = if (policy.overtimeEnabled && schedule.workType == WorkType.OVERTIME)
        (wage * (policy.overtimePercent / 100.0) * paidHours).roundToLong() else 0L

    val holidayAdd = if (policy.holidayEnabled && schedule.workType == WorkType.HOLIDAY)
        (wage * (policy.holidayPercent / 100.0) * paidHours).roundToLong() else 0L

    val nightAdd = if (policy.nightEnabled && nightMin > 0)
        (wage * (policy.nightPercent / 100.0) * nightHours).roundToLong() else 0L

    val weeklyAdd = 0L // 시프트 단위에선 0, 월합계에서만 계산

    val gross = base + overtimeAdd + holidayAdd + nightAdd + weeklyAdd
    val insuranceAmt = (gross * insurancePercent(insurance)).roundToLong()
    val taxAmt = (gross * taxPercent(tax)).roundToLong()
    val net = gross - insuranceAmt - taxAmt

    return PayBreakdown(
        paidMinutes = paidMin,
        nightMinutes = nightMin,
        basePay = base,
        overtimeAdd = overtimeAdd,
        holidayAdd = holidayAdd,
        nightAdd = nightAdd,
        weeklyHolidayAdd = weeklyAdd,
        gross = gross,
        insurance = insuranceAmt,
        tax = taxAmt,
        net = net
    )
}

/** 한 달 합계 계산 (주휴수당 주단위 요건 반영) */
fun computeMonthlySummary(
    alba: UICalendarAlba,
    schedules: List<UICalendarSchedule>,   // 같은 달의 스케줄만 넘겨주세요
    dates: List<LocalDate>,                // 위 스케줄의 (year,month,day)로 만든 LocalDate들
    tax: TaxConfig,
    insurance: InsuranceConfig,
    policy: SurchargePolicy
): MonthlySummary {
    var base = 0L
    var over = 0L
    var hol = 0L
    var night = 0L
    var paidTotalMin = 0
    var nightTotalMin = 0

    schedules.forEachIndexed { idx, s ->
        val per = computeShiftPay(alba, s, tax = TaxConfig.NONE, insurance = InsuranceConfig.NONE, policy = policy)
        // (월합계에서 공제는 전체 gross 기준으로 한 번만 수행하니 여기선 제외)
        base += per.basePay
        over += per.overtimeAdd
        hol += per.holidayAdd
        night += per.nightAdd
        paidTotalMin += per.paidMinutes
        nightTotalMin += per.nightMinutes
    }

    // 주휴수당(주 15시간 이상이면, 그 주의 "평균 1일 근무시간" 유급 1일분 추가) – 일요일~토요일 기준
    val weeklyAdd = if (policy.weeklyHolidayEnabled)
        weeklyHolidayAddMinutes(schedules, dates).let { minutes ->
            val wage = (schedules.firstOrNull()?.overrideHourlyWage ?: alba.hourlyWage).toDouble()
            (wage * (minutes / 60.0)).roundToLong()
        }
    else 0L

    val gross = base + over + hol + night + weeklyAdd
    val insuranceAmt = (gross * insurancePercent(insurance)).roundToLong()
    val taxAmt = (gross * taxPercent(tax)).roundToLong()
    val net = gross - insuranceAmt - taxAmt

    return MonthlySummary(
        basePay = base,
        overtimeAdd = over,
        holidayAdd = hol,
        nightAdd = night,
        weeklyHolidayAdd = weeklyAdd,
        gross = gross,
        insurance = insuranceAmt,
        tax = taxAmt,
        net = net,
        totalPaidMinutes = paidTotalMin,
        totalNightMinutes = nightTotalMin
    )
}

/* ===================== 내부 유틸(시간, 요율, 주휴) ===================== */

/** 자정 넘김 포함 유급분(분) */
private fun paidMinutes(startH: Int, startM: Int, endH: Int, endM: Int, breakMin: Int): Int {
    val s = startH * 60 + startM
    var e = endH * 60 + endM
    var dur = e - s
    if (dur <= 0) dur += 24 * 60 // 자정 넘김
    return max(0, dur - breakMin)
}

/** 시프트의 야간(22:00~06:00) 분. 자정 넘김 고려. */
private fun nightMinutes(startH: Int, startM: Int, endH: Int, endM: Int): Int {
    val s = startH * 60 + startM
    var e = endH * 60 + endM
    if (e <= s) e += 24 * 60

    // 기준일의 윈도우: [0,360), [1320,1440)
    val day = (s / 1440) * 1440
    val windows = listOf(
        day + 0 to day + 360,           // 00:00~06:00
        day + 1320 to day + 1440,       // 22:00~24:00
        day + 1440 + 0 to day + 1440 + 360,
        day + 1440 + 1320 to day + 1440 + 1440
    )

    var sum = 0
    for ((ws, we) in windows) {
        val a = max(s, ws)
        val b = max(a, minOf(e, we))
        if (b > a) sum += (b - a)
    }
    return sum
}

/** 세금 퍼센트(소수). 3.3%/6.6%/직접 */
private fun taxPercent(tax: TaxConfig): Double = when (tax) {
    is TaxConfig.CustomPercent -> (tax.percent / 100.0).coerceAtLeast(0.0)
    TaxConfig.Biz33 -> 0.033
    TaxConfig.Day66 -> 0.066
    TaxConfig.NONE -> 0.0
}

/**
 * 근로자 부담 보험 퍼센트(소수).
 * - 미가입: 0%
 * - 고용보험만: 0.9%
 * - 4대보험(대략치): 국민연금 4.5% + 건강보험 3.545% + 장기요양(건강의 12.95% ≈ 0.459%) + 고용보험 0.9% ≈ 9.404%
 *   ※ 실제율은 해마다 변동 가능 → 나중에 설정화 가능.
 */
private fun insurancePercent(ins: InsuranceConfig): Double = when (ins) {
    InsuranceConfig.NONE -> 0.0
    InsuranceConfig.EmploymentOnly -> 0.009
    InsuranceConfig.Four -> (0.045 + 0.03545 + 0.03545 * 0.1295 + 0.009) // ≈ 0.09404
}

/**
 * 주휴수당 추가 '분' 계산.
 * 규칙(간이):
 *  - 기준: 일요일~토요일 1주
 *  - 해당 주 유급시간 합계 ≥ 15시간이면, 그 주의 평균 1일 근무시간(= 주 총유급시간 / 그 주의 실제 근무일수)을 유급으로 1회 추가
 *  - 반환값: 월 전체의 "추가 유급 분" 총합
 */
private fun weeklyHolidayAddMinutes(
    schedules: List<UICalendarSchedule>,
    dates: List<LocalDate>
): Int {
    if (schedules.isEmpty()) return 0
    // weekKey: 그 주 일요일 날짜
    fun weekKey(d: LocalDate): LocalDate {
        val dow = d.dayOfWeek.value // Mon=1..Sun=7
        val minus = if (dow == 7) 0L else dow.toLong()
        return d.minusDays(minus)
    }

    data class Acc(var totalMin: Int = 0, val days: MutableSet<LocalDate> = linkedSetOf())

    val byWeek = mutableMapOf<LocalDate, Acc>()
    schedules.forEachIndexed { i, s ->
        val date = dates[i] // 스케줄과 같은 순서로 전달 가정
        val wk = weekKey(date)
        val paid = paidMinutes(s.startHour, s.startMinute, s.endHour, s.endMinute, s.breakMinutes)
        val acc = byWeek.getOrPut(wk) { Acc() }
        acc.totalMin += paid
        acc.days += date
    }

    var bonusMin = 0
    byWeek.values.forEach { acc ->
        if (acc.totalMin >= 15 * 60) {
            val avgDaily = (acc.totalMin / max(1, acc.days.size))
            bonusMin += avgDaily
        }
    }
    return bonusMin
}
