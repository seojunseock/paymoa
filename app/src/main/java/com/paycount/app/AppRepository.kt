package com.paycount.app

import com.paycount.app.ui.alba.AlbaFormInitial
import com.paycount.app.ui.alba.AlbaFormResult
import com.paycount.app.ui.alba.InsuranceConfig
import com.paycount.app.ui.alba.SurchargePolicy
import com.paycount.app.ui.alba.TaxConfig
import com.paycount.app.ui.alba.UICalendarAlba
import com.paycount.app.ui.alba.UICalendarSchedule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.LocalDate
import java.util.UUID

/* ---------------- 폼에서 저장한 기본 근무 템플릿 ---------------- */

data class DefaultShiftTemplate(
    val startH: Int, val startM: Int,
    val endH: Int, val endM: Int,
    val breakMin: Int
)

/* ---------------- 알바 프로필(세금/보험/가산정책 포함 스냅샷) ---------------- */

data class AlbaProfileSnapshot(
    val alba: UICalendarAlba,
    val tax: TaxConfig = TaxConfig.NONE,
    val insurance: InsuranceConfig = InsuranceConfig.NONE,
    val surcharge: SurchargePolicy = SurchargePolicy(),
    val defaultShift: DefaultShiftTemplate? = null
)

/* ---------------- 프로필 수정용 패치 ---------------- */

data class AlbaPatch(
    val name: String? = null,
    val colorHex: String? = null,
    val hourlyWage: Long? = null,
    val payDay: Int? = null,
    val tax: TaxConfig? = null,
    val insurance: InsuranceConfig? = null,
    val surcharge: SurchargePolicy? = null,
    val defaultShift: DefaultShiftTemplate? = null
)

/* ---------------- 저장소 인터페이스 ---------------- */

interface AppRepository {
    val albas: StateFlow<List<UICalendarAlba>>
    val schedules: StateFlow<List<UICalendarSchedule>>

    fun getProfile(albaId: String): AlbaProfileSnapshot

    /** 폼 프리필용: 수정 진입 시 전체 기본값을 반환 */
    fun getFormInitial(albaId: String): AlbaFormInitial

    /** 신규 저장 */
    fun saveAlbaForm(result: AlbaFormResult)

    /** 기존 알바 수정(부분 패치) */
    fun updateAlba(albaId: String, patch: AlbaPatch)

    /** 기존 알바 수정(폼 전체 결과로 저장 + 스케줄 날짜 업서트) */
    fun updateAlbaFromForm(albaId: String, result: AlbaFormResult)

    fun addSchedule(s: UICalendarSchedule)
    fun updateSchedule(s: UICalendarSchedule)
    fun deleteSchedule(id: String)

    fun applyWageForward(
        albaId: String,
        y: Int, m: Int, d: Int,
        startMin: Int,
        newWage: Long
    )

    fun setScheduleWage(scheduleId: String, wage: Long?)
}

/* ---------------- 인메모리 구현 ---------------- */

class InMemoryAppRepository : AppRepository {

    /** key = albaId */
    private val profiles = linkedMapOf<String, AlbaProfileSnapshot>()

    private val _albas = MutableStateFlow<List<UICalendarAlba>>(emptyList())
    override val albas: StateFlow<List<UICalendarAlba>> = _albas

    private val _schedules = MutableStateFlow<List<UICalendarSchedule>>(emptyList())
    override val schedules: StateFlow<List<UICalendarSchedule>> = _schedules

    override fun getProfile(albaId: String): AlbaProfileSnapshot {
        return profiles[albaId]
            ?: error("Profile not found for albaId=$albaId")
    }

    override fun getFormInitial(albaId: String): AlbaFormInitial {
        val prof = getProfile(albaId)
        val alba = prof.alba

        // 시간 템플릿 없으면 해당 알바 스케줄 하나를 참고, 그것도 없으면 기본값
        val tpl = prof.defaultShift ?: run {
            val any = _schedules.value.firstOrNull { it.albaId == albaId }
            if (any != null) {
                DefaultShiftTemplate(
                    startH = any.startHour, startM = any.startMinute,
                    endH = any.endHour, endM = any.endMinute,
                    breakMin = any.breakMinutes
                )
            } else {
                DefaultShiftTemplate(9, 0, 18, 0, 0)
            }
        }

        val selectedDates: Set<LocalDate> = _schedules.value
            .filter { it.albaId == albaId }
            .map { LocalDate.of(it.year, it.month, it.day) }
            .toSet()

        return AlbaFormInitial(
            storeName = alba.name,
            hourlyWage = alba.hourlyWage,
            tax = prof.tax,
            insurance = prof.insurance,
            surcharge = prof.surcharge,
            startHour24 = tpl.startH,
            startMinute = tpl.startM,
            endHour24 = tpl.endH,
            endMinute = tpl.endM,
            breakMinutes = tpl.breakMin,
            selectedDates = selectedDates,
            colorHex = alba.colorHex,
            payDay = alba.payDay
        )
    }

    override fun saveAlbaForm(result: AlbaFormResult) {
        val id = UUID.randomUUID().toString()

        // 매장명 중복 방지: 같은 이름 있으면 "편의점", "편의점 (2)", "편의점 (3)" …
        val uniqueName = generateUniqueName(result.storeName)

        val alba = UICalendarAlba(
            id = id,
            name = uniqueName,
            colorHex = result.colorHex,
            hourlyWage = result.hourlyWage,
            payDay = result.payDay
        )

        profiles[id] = AlbaProfileSnapshot(
            alba = alba,
            tax = result.tax,
            insurance = result.insurance,
            surcharge = result.surcharge ?: SurchargePolicy(),
            defaultShift = DefaultShiftTemplate(
                startH = result.startHour24,
                startM = result.startMinute,
                endH = result.endHour24,
                endM = result.endMinute,
                breakMin = result.breakMinutes
            )
        )

        _albas.value = profiles.values.map { it.alba }

        // 사용자가 폼에서 날짜들을 선택한 경우, 기본 템플릿으로 스케줄 생성
        if (result.selectedDates.isNotEmpty()) {
            val add = result.selectedDates.map { d ->
                UICalendarSchedule(
                    albaId = id,
                    year = d.year, month = d.monthValue, day = d.dayOfMonth,
                    startHour = result.startHour24, startMinute = result.startMinute,
                    endHour = result.endHour24, endMinute = result.endMinute,
                    breakMinutes = result.breakMinutes
                )
            }
            _schedules.value = _schedules.value + add
        }
    }

    override fun updateAlba(albaId: String, patch: AlbaPatch) {
        val cur = profiles[albaId] ?: return
        val newName = patch.name?.let { desired ->
            if (desired == cur.alba.name) desired else generateUniqueName(desired, excludeId = albaId)
        }

        val newAlba = cur.alba.copy(
            name = newName ?: cur.alba.name,
            colorHex = patch.colorHex ?: cur.alba.colorHex,
            hourlyWage = patch.hourlyWage ?: cur.alba.hourlyWage,
            payDay = patch.payDay ?: cur.alba.payDay
        )

        profiles[albaId] = cur.copy(
            alba = newAlba,
            tax = patch.tax ?: cur.tax,
            insurance = patch.insurance ?: cur.insurance,
            surcharge = patch.surcharge ?: cur.surcharge,
            defaultShift = patch.defaultShift ?: cur.defaultShift
        )
        _albas.value = profiles.values.map { it.alba }
    }

    override fun updateAlbaFromForm(albaId: String, result: AlbaFormResult) {
        // 1) 프로필 업데이트
        val current = profiles[albaId] ?: return
        val uniqueName =
            if (result.storeName == current.alba.name) result.storeName
            else generateUniqueName(result.storeName, excludeId = albaId)

        val updatedAlba = current.alba.copy(
            name = uniqueName,
            colorHex = result.colorHex,
            hourlyWage = result.hourlyWage,
            payDay = result.payDay
        )
        profiles[albaId] = current.copy(
            alba = updatedAlba,
            tax = result.tax,
            insurance = result.insurance,
            surcharge = result.surcharge ?: SurchargePolicy(),
            defaultShift = DefaultShiftTemplate(
                startH = result.startHour24,
                startM = result.startMinute,
                endH = result.endHour24,
                endM = result.endMinute,
                breakMin = result.breakMinutes
            )
        )
        _albas.value = profiles.values.map { it.alba }

        // 2) 스케줄 업서트(같은 날짜 있으면 수정, 없으면 추가)
        if (result.selectedDates.isNotEmpty()) {
            val base = _schedules.value.toMutableList()
            for (d in result.selectedDates) {
                val idx = base.indexOfFirst {
                    it.albaId == albaId && it.year == d.year && it.month == d.monthValue && it.day == d.dayOfMonth
                }
                if (idx >= 0) {
                    val old = base[idx]
                    base[idx] = old.copy(
                        startHour = result.startHour24,
                        startMinute = result.startMinute,
                        endHour = result.endHour24,
                        endMinute = result.endMinute,
                        breakMinutes = result.breakMinutes
                    )
                } else {
                    base += UICalendarSchedule(
                        albaId = albaId,
                        year = d.year, month = d.monthValue, day = d.dayOfMonth,
                        startHour = result.startHour24, startMinute = result.startMinute,
                        endHour = result.endHour24, endMinute = result.endMinute,
                        breakMinutes = result.breakMinutes
                    )
                }
            }
            _schedules.value = base
        }
    }

    override fun addSchedule(s: UICalendarSchedule) {
        _schedules.value = _schedules.value + s
    }

    override fun updateSchedule(s: UICalendarSchedule) {
        _schedules.value = _schedules.value.map { if (it.id == s.id) s else it }
    }

    override fun deleteSchedule(id: String) {
        _schedules.value = _schedules.value.filterNot { it.id == id }
    }

    override fun applyWageForward(
        albaId: String,
        y: Int, m: Int, d: Int,
        startMin: Int,
        newWage: Long
    ) {
        _schedules.value = _schedules.value.map { s ->
            if (s.albaId != albaId) return@map s
            val sameDay = (s.year == y && s.month == m && s.day == d)
            val laterDay =
                (s.year > y) ||
                        (s.year == y && s.month > m) ||
                        (s.year == y && s.month == m && s.day > d)
            val after = laterDay || (sameDay && (s.startHour * 60 + s.startMinute) >= startMin)
            if (after) s.copy(overrideHourlyWage = newWage) else s
        }
    }

    override fun setScheduleWage(scheduleId: String, wage: Long?) {
        _schedules.value = _schedules.value.map {
            if (it.id == scheduleId) it.copy(overrideHourlyWage = wage) else it
        }
    }

    /* ---------------- 내부 유틸: 매장명 중복 방지 ---------------- */

    private fun generateUniqueName(desired: String, excludeId: String? = null): String {
        val existing = profiles
            .filterKeys { it != excludeId }
            .values.map { it.alba.name }.toSet()

        if (desired !in existing) return desired

        var idx = 2
        while (true) {
            val cand = "$desired ($idx)"
            if (cand !in existing) return cand
            idx++
        }
    }
}

/* ---------------- 팩토리: 인메모리 저장소 생성 ---------------- */

fun createInMemoryRepository(): AppRepository = InMemoryAppRepository()
