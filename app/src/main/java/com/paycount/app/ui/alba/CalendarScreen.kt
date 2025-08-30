@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui.alba

import android.icu.text.DecimalFormat
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.paycount.app.common.BreakSheet
import com.paycount.app.common.TimeSheet
import java.time.LocalDate
import java.util.Calendar
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

// PayrollEngine(세전/세후 계산)
import com.paycount.app.payroll.*   // computeShiftPay, computeMonthlySummary

/* 표시용 근무유형 */
private enum class UiWorkType { 기본, 대타, 연장, 휴일, 야간 }

/* 프리뷰 DTO */
private data class Preview(val previewHourly: Long, val previewTotal: Long)

/* -------------------------------------------------------------------------- */
/* 달력 화면                                                                   */
/* -------------------------------------------------------------------------- */

@Composable
fun CalendarScreen(
    onBack: () -> Unit,

    /* 알바/스케줄 (상위에서 상태 관리) */
    albas: List<UICalendarAlba>,
    schedules: List<UICalendarSchedule>,

    /* CRUD 콜백 */
    onDeleteSchedule: (String) -> Unit,
    onUpdateSchedule: (UICalendarSchedule) -> Unit,
    onAddSchedule: (UICalendarSchedule) -> Unit,

    /* “그 근무 이후 시급 일괄 적용” */
    onApplyWageForward: (
        albaId: String,
        effectiveY: Int, effectiveM: Int, effectiveD: Int,
        effectiveStartMinutes: Int,
        newWage: Long
    ) -> Unit,

    /* 정책 조회/저장 */
    getSurchargePolicy: (albaId: String) -> SurchargePolicy?,
    saveSurchargePolicy: (albaId: String, policy: SurchargePolicy?) -> Unit,

    /* 세금/보험 조회(없으면 기본 없음) */
    getTaxPolicy: (albaId: String) -> TaxConfig? = { null },
    getInsurancePolicy: (albaId: String) -> InsuranceConfig? = { null },

    /* 필요 시 폼 이동 */
    goToAlbaForm: (albaId: String) -> Unit
) {
    val ctx = LocalContext.current

    var ym by remember { mutableStateOf(YearMonthCompat.now()) }
    var activeIds by remember { mutableStateOf(albas.map { it.id }.toSet()) }
    var sheetDay by remember { mutableStateOf<Triple<Int, Int, Int>?>(null) }

    // 수정 시트 상태
    var editingAlba by remember { mutableStateOf<UICalendarAlba?>(null) }
    var editingDate by remember { mutableStateOf<Triple<Int, Int, Int>?>(null) }
    var drafts by remember { mutableStateOf(listOf<SegmentDraft>()) }
    var step by remember { mutableStateOf<EditStep>(EditStep.List) }
    val wageInlineEditing = remember { mutableStateMapOf<Int, Boolean>() }
    val wageForwardChecked = remember { mutableStateMapOf<Int, Boolean>() }

    // 근무 추가 시트
    var showAddSheet by remember { mutableStateOf(false) }
    var addDate by remember { mutableStateOf<Triple<Int, Int, Int>?>(null) }

    // 알바 없음 안내
    var showNoAlbaDialog by remember { mutableStateOf(false) }

    // 겹침 경고 팝업
    var overlapMsg by remember { mutableStateOf<String?>(null) }

    val df = remember { DecimalFormat("#,###") }
    val sundayColor = Color(0xFFE53935)
    val saturdayColor = Color(0xFF1E88E5)

    // 이달 합계(세후)
    val monthTotal by remember(ym, activeIds, schedules, albas) {
        mutableStateOf(
            run {
                var sum = 0L
                val albaMap = albas.associateBy { it.id }
                val firstDay = LocalDate.of(ym.year, ym.month, 1)
                val lastDay = firstDay.withDayOfMonth(firstDay.lengthOfMonth())
                val monthDates = generateSequence(firstDay) { d ->
                    val n = d.plusDays(1)
                    if (n <= lastDay) n else null
                }.toList()

                activeIds.forEach { aid ->
                    val alba = albaMap[aid] ?: return@forEach
                    val monthSchedules = schedules.filter { it.albaId == aid && it.year == ym.year && it.month == ym.month }
                    if (monthSchedules.isEmpty()) return@forEach

                    val tax = getTaxPolicy(aid) ?: TaxConfig.NONE
                    val ins = getInsurancePolicy(aid) ?: InsuranceConfig.NONE
                    val pol = getSurchargePolicy(aid) ?: SurchargePolicy()

                    val summary = computeMonthlySummary(
                        alba = alba,
                        schedules = monthSchedules,
                        dates = monthDates,
                        tax = tax,
                        insurance = ins,
                        policy = pol
                    )
                    sum += summary.net
                }
                sum
            }
        )
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                navigationIcon = { TextButton(onClick = onBack) { Text("‹  뒤로") } },
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = { ym = ym.prev() }) { Text("<") }
                        Spacer(Modifier.width(6.dp))
                        Text("${ym.year}년 ${ym.month}월", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.width(6.dp))
                        TextButton(onClick = { ym = ym.next() }) { Text(">") }
                    }
                }
            )
        }
    ) { inner ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "이달 예상 합계(세후)",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.width(12.dp))
                    Text("${df.format(monthTotal)}원", fontWeight = FontWeight.Bold)
                }
            }

            Row(
                Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically
            ) {
                albas.forEach { a ->
                    val on = a.id in activeIds
                    AlbaChip(
                        name = a.name,
                        color = parseColor(a.colorHex),
                        checked = on,
                        onToggle = {
                            activeIds = activeIds.toMutableSet().apply { if (on) remove(a.id) else add(a.id) }
                        }
                    )
                    Spacer(Modifier.width(8.dp))
                }
            }

            CalendarGrid(
                ym = ym,
                albas = albas,
                activeIds = activeIds,
                schedules = schedules,
                sundayColor = sundayColor,
                saturdayColor = saturdayColor,
                onDayClick = { y, m, d -> sheetDay = Triple(y, m, d) }
            )
        }
    }

    /* ---------------- 하루 상세 시트 ---------------- */
    sheetDay?.let { (y, m, day) ->
        val daily = schedules
            .filter { it.year == y && it.month == m && it.day == day && it.albaId in activeIds }
            .sortedWith(compareBy({ it.albaId }, { it.startHour }, { it.startMinute }))

        ModalBottomSheet(onDismissRequest = { sheetDay = null }) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text("${y}년 ${m}월 ${day}일", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.weight(1f))
                    TextButton(
                        onClick = {
                            sheetDay = null
                            if (albas.isEmpty()) {
                                showNoAlbaDialog = true
                            } else {
                                addDate = Triple(y, m, day)
                                showAddSheet = true
                            }
                        }
                    ) { Text("근무 추가") }
                }
                Spacer(Modifier.height(8.dp))

                if (daily.isEmpty()) {
                    Text("활성화된 알바의 근무가 없어요.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    val albaMap = albas.associateBy { it.id }
                    daily.groupBy { it.albaId }.forEach { (aid, listRaw) ->
                        val alba = albaMap[aid] ?: return@forEach
                        val list = listRaw.sortedWith(compareBy({ it.startHour }, { it.startMinute }))

                        val tax = getTaxPolicy(aid) ?: TaxConfig.NONE
                        val ins = getInsurancePolicy(aid) ?: InsuranceConfig.NONE
                        val pol = getSurchargePolicy(aid) ?: SurchargePolicy()

                        val dayNet = list.sumOf { s ->
                            val breakdown = computeShiftPay(
                                alba = alba,
                                schedule = s,
                                tax = tax,
                                insurance = ins,
                                policy = pol
                            )
                            breakdown.net
                        }

                        Card(
                            Modifier.fillMaxWidth().padding(vertical = 6.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                        ) {
                            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(
                                        Modifier.size(10.dp).clip(RoundedCornerShape(50))
                                            .background(parseColor(alba.colorHex))
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(alba.name, fontWeight = FontWeight.SemiBold)
                                    Spacer(Modifier.weight(1f))
                                    Text("${df.format(dayNet)}원", fontWeight = FontWeight.Bold)
                                }
                                Spacer(Modifier.height(6.dp))

                                list.forEach { s ->
                                    val overnightSeg = (s.endHour * 60 + s.endMinute) <= (s.startHour * 60 + s.startMinute)
                                    Text("• ${fmtAmPm(s.startHour, s.startMinute)} ~ ${fmtAmPm(s.endHour, s.endMinute)}${if (overnightSeg) " (다음날)" else ""}  (휴게 ${s.breakMinutes}분)")
                                }

                                Spacer(Modifier.height(10.dp))
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    OutlinedButton(
                                        onClick = { onDeleteSchedule(list.last().id) },
                                        modifier = Modifier.weight(1f)
                                    ) { Text("삭제(마지막 구간)") }

                                    Button(
                                        onClick = {
                                            // 수정 시트
                                            editingAlba = alba
                                            editingDate = Triple(y, m, day)
                                            drafts = list.map {
                                                SegmentDraft(
                                                    id = it.id,
                                                    startH = it.startHour, startM = it.startMinute,
                                                    endH = it.endHour, endM = it.endMinute,
                                                    breakMin = it.breakMinutes,
                                                    overrideWage = it.overrideHourlyWage
                                                )
                                            }
                                            wageInlineEditing.clear()
                                            wageForwardChecked.clear()
                                            drafts.indices.forEach { idx ->
                                                wageInlineEditing[idx] = false
                                                wageForwardChecked[idx] = false
                                            }
                                            step = EditStep.List
                                        },
                                        modifier = Modifier.weight(1f)
                                    ) { Text("수정") }
                                }
                            }
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))
                Button(onClick = { sheetDay = null }, modifier = Modifier.fillMaxWidth()) { Text("닫기") }
                Spacer(Modifier.height(8.dp))
            }
        }
    }

    /* ---------------- 근무 추가 시트 ---------------- */
    val addTriple = addDate
    if (showAddSheet && addTriple != null) {
        val (y, m, day) = addTriple
        var selectedAlbaId by remember(addTriple) { mutableStateOf<String?>(null) }
        var workType by remember(addTriple) { mutableStateOf<UiWorkType?>(null) }

        var sH by remember(addTriple) { mutableStateOf(9) }
        var sM by remember(addTriple) { mutableStateOf(0) }
        var eH by remember(addTriple) { mutableStateOf(18) }
        var eM by remember(addTriple) { mutableStateOf(0) }
        var br by remember(addTriple) { mutableStateOf(0) }

        val selectedAlba = albas.firstOrNull { it.id == selectedAlbaId }
        val policy: SurchargePolicy? = selectedAlba?.id?.let { getSurchargePolicy(it) }
        val tax = selectedAlba?.id?.let(getTaxPolicy) ?: TaxConfig.NONE
        val ins = selectedAlba?.id?.let(getInsurancePolicy) ?: InsuranceConfig.NONE

        // 프리뷰(세후)
        val preview by remember(selectedAlba, policy, tax, ins, workType, sH, sM, eH, eM, br) {
            mutableStateOf(
                run {
                    val alba = selectedAlba ?: return@run Preview(0, 0)
                    val mappedType = when (workType) {
                        UiWorkType.연장 -> WorkType.OVERTIME
                        UiWorkType.휴일 -> WorkType.HOLIDAY
                        UiWorkType.야간 -> WorkType.NIGHT
                        UiWorkType.대타 -> WorkType.SUBSTITUTE
                        else -> WorkType.BASIC
                    }

                    val temp = UICalendarSchedule(
                        albaId = alba.id,
                        year = y, month = m, day = day,
                        startHour = sH, startMinute = sM,
                        endHour = eH, endMinute = eM,
                        breakMinutes = br,
                        overrideHourlyWage = null,
                        workType = mappedType
                    )

                    val r = computeShiftPay(
                        alba = alba,
                        schedule = temp,
                        tax = tax,
                        insurance = ins,
                        policy = policy ?: SurchargePolicy()
                    )
                    val paid = ((eH * 60 + eM) - (sH * 60 + sM)).let { if (it <= 0) it + 24 * 60 else it } - br
                    val effHourly = if (paid > 0) (r.net * 60.0 / paid).roundToLong() else alba.hourlyWage
                    Preview(previewHourly = effHourly, previewTotal = r.net)
                }
            )
        }

        var showTimePicker by remember { mutableStateOf(false) }
        var showBreakPicker by remember { mutableStateOf(false) }

        // 정책 인라인 편집
        var inlineEditFor by remember { mutableStateOf<UiWorkType?>(null) }

        ModalBottomSheet(onDismissRequest = { showAddSheet = false }) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {

                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { showAddSheet = false }) { Text("‹ 뒤로") }
                    Spacer(Modifier.weight(1f))
                    Text("${y}년 ${m}월 ${day}일 근무 추가", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.weight(1f))
                }

                // 알바 선택
                Text("어떤 알바인가요?", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.horizontalScroll(rememberScrollState())) {
                    albas.forEach { a ->
                        ChoiceChip(
                            text = a.name,
                            color = parseColor(a.colorHex),
                            selected = a.id == selectedAlbaId,
                            onClick = { selectedAlbaId = a.id }
                        )
                        Spacer(Modifier.width(8.dp))
                    }
                }

                HorizontalDivider()

                // 근무 유형
                Text("근무 유형", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.horizontalScroll(rememberScrollState())) {
                    listOf(UiWorkType.기본, UiWorkType.대타, UiWorkType.연장, UiWorkType.휴일, UiWorkType.야간).forEach { t ->
                        AssistChip(
                            onClick = {
                                if (selectedAlbaId == null) {
                                    Toast.makeText(ctx, "먼저 알바를 선택해 주세요.", Toast.LENGTH_SHORT).show()
                                    return@AssistChip
                                }
                                val pol = getSurchargePolicy(selectedAlbaId!!)
                                val needPolicy = when (t) {
                                    UiWorkType.연장 -> pol?.overtimeEnabled != true
                                    UiWorkType.휴일 -> pol?.holidayEnabled != true
                                    UiWorkType.야간 -> pol?.nightEnabled != true
                                    else -> false
                                }
                                if (needPolicy) {
                                    Toast.makeText(ctx, "가산정책이 설정되어 있지 않습니다. 지금 설정할게요.", Toast.LENGTH_SHORT).show()
                                    inlineEditFor = t
                                } else {
                                    workType = t
                                }
                            },
                            label = { Text(t.name) },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = if (workType == t) MaterialTheme.colorScheme.primary.copy(0.12f)
                                else MaterialTheme.colorScheme.surfaceVariant
                            )
                        )
                        Spacer(Modifier.width(8.dp))
                    }
                }

                // 근무 시간
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("근무 시간")
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { showTimePicker = true }) {
                        Text("${fmtAmPm(sH, sM)} ~ ${fmtAmPm(eH, eM)}" + if ((eH*60+eM) <= (sH*60+sM)) " (다음날)" else "")
                    }
                }
                if (showTimePicker) {
                    TimeSheet(
                        startH = sH, startM = sM, endH = eH, endM = eM,
                        onDismiss = { showTimePicker = false },
                        onDone = { sh, sm, eh, em ->
                            sH = sh; sM = sm; eH = eh; eM = em
                            showTimePicker = false
                        }
                    )
                }

                // 휴게시간
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("휴게시간")
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { showBreakPicker = true }) { Text("${br}분") }
                }
                if (showBreakPicker) {
                    BreakSheet(
                        initial = br,
                        onDismiss = { showBreakPicker = false },
                        onDone = { mnt -> br = mnt; showBreakPicker = false }
                    )
                }

                // 프리뷰
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row {
                            Text("적용 시급 미리보기: ", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(6.dp))
                            Text(if (preview.previewHourly > 0) "${df.format(preview.previewHourly)} 원" else "—")
                        }
                        Row {
                            Text("예상 실수령(세후): ", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(6.dp))
                            Text(if (preview.previewTotal > 0) "${df.format(preview.previewTotal)} 원" else "—")
                        }
                    }
                }

                Button(
                    onClick = {
                        val alba = selectedAlba ?: return@Button
                        val mappedType = when (workType) {
                            UiWorkType.연장 -> WorkType.OVERTIME
                            UiWorkType.휴일 -> WorkType.HOLIDAY
                            UiWorkType.야간 -> WorkType.NIGHT
                            UiWorkType.대타 -> WorkType.SUBSTITUTE
                            else -> WorkType.BASIC
                        }

                        fun toMin(h: Int, m: Int) = h * 60 + m
                        var newStart = toMin(sH, sM)
                        var newEnd   = toMin(eH, eM)
                        if (newEnd <= newStart) newEnd += 24 * 60

                        val base = LocalDate.of(y, m, day)

                        fun normSpan(sc: UICalendarSchedule): Pair<Int, Int> {
                            val d = LocalDate.of(sc.year, sc.month, sc.day)
                            var s = sc.startHour * 60 + sc.startMinute
                            var e = sc.endHour * 60 + sc.endMinute
                            if (e <= s) e += 24 * 60
                            val off = when {
                                d.isEqual(base.minusDays(1)) -> -1
                                d.isEqual(base) -> 0
                                d.isEqual(base.plusDays(1)) -> 1
                                else -> Int.MAX_VALUE
                            }
                            if (off == Int.MAX_VALUE) return Int.MAX_VALUE to Int.MIN_VALUE
                            s += off * 24 * 60
                            e += off * 24 * 60
                            return s to e
                        }

                        fun overlap(aS: Int, aE: Int, bS: Int, bE: Int) = (aS < bE && bS < aE)
                        fun overlapOrTouch(aS: Int, aE: Int, bS: Int, bE: Int) = (aS <= bE && bS <= aE)

                        val spansAll = schedules
                            .map { it to normSpan(it) }
                            .filter { it.second.first != Int.MAX_VALUE }

                        val hasStrictConflict = spansAll.any { (sc, span) ->
                            val (s, e) = span
                            val hit = overlap(newStart, newEnd, s, e)
                            if (!hit) false
                            else {
                                val isSameDayBasic =
                                    (sc.albaId == alba.id && sc.workType == WorkType.BASIC &&
                                            LocalDate.of(sc.year, sc.month, sc.day).isEqual(base))
                                val weAreBasic = (mappedType == WorkType.BASIC)
                                !(weAreBasic && isSameDayBasic)
                            }
                        }
                        if (hasStrictConflict) {
                            overlapMsg = "겹치는 근무가 있습니다."
                            return@Button
                        }

                        // BASIC 병합(당일 기준) — 오버나이트 포함
                        if (mappedType == WorkType.BASIC) {
                            val sameDay = schedules.filter { it.year == y && it.month == m && it.day == day }
                            val mergeTargets = sameDay.filter { sc ->
                                sc.albaId == alba.id && sc.workType == WorkType.BASIC
                            }.filter { sc ->
                                val (s, e) = normSpan(sc)
                                overlapOrTouch(newStart, newEnd, s, e)
                            }

                            if (mergeTargets.isNotEmpty()) {
                                val mergedStart = min(newStart, mergeTargets.minOf { normSpan(it).first })
                                val mergedEnd   = max(newEnd,   mergeTargets.maxOf { normSpan(it).second })
                                val mergedBreak = br + mergeTargets.sumOf { it.breakMinutes }

                                mergeTargets.forEach { onDeleteSchedule(it.id) }

                                fun hOf(min: Int) = (min % (24 * 60) + (24 * 60)) % (24 * 60) / 60
                                fun mOf(min: Int) = (min % (24 * 60) + (24 * 60)) % (24 * 60) % 60

                                onAddSchedule(
                                    UICalendarSchedule(
                                        albaId = alba.id,
                                        year = y, month = m, day = day,
                                        startHour = hOf(mergedStart),
                                        startMinute = mOf(mergedStart),
                                        endHour = hOf(mergedEnd),
                                        endMinute = mOf(mergedEnd),
                                        breakMinutes = mergedBreak,
                                        overrideHourlyWage = null,
                                        workType = WorkType.BASIC
                                    )
                                )
                                showAddSheet = false
                                return@Button
                            }
                        }

                        // 일반 추가
                        fun hOf(min: Int) = (min % (24 * 60) + (24 * 60)) % (24 * 60) / 60
                        fun mOf(min: Int) = (min % (24 * 60) + (24 * 60)) % (24 * 60) % 60

                        onAddSchedule(
                            UICalendarSchedule(
                                albaId = alba.id,
                                year = y, month = m, day = day,
                                startHour = hOf(newStart),
                                startMinute = mOf(newStart),
                                endHour = hOf(newEnd),
                                endMinute = mOf(newEnd),
                                breakMinutes = br,
                                overrideHourlyWage = null,
                                workType = mappedType
                            )
                        )
                        showAddSheet = false
                    },
                    enabled = selectedAlbaId != null && workType != null,
                    modifier = Modifier.fillMaxWidth()
                ) { Text("저장하기") }
            }
        }

        // 가산정책 인라인 설정
        inlineEditFor?.let { t ->
            val albaId = selectedAlbaId ?: return@let
            SurchargeInlineEditor(
                title = when (t) {
                    UiWorkType.연장 -> "연장 가산율 설정"
                    UiWorkType.휴일 -> "휴일 가산율 설정"
                    UiWorkType.야간 -> "야간 가산율 설정"
                    else -> ""
                },
                current = getSurchargePolicy(albaId) ?: SurchargePolicy(),
                targetType = t,
                onClose = { inlineEditFor = null },
                onSave = { newPolicy ->
                    saveSurchargePolicy(albaId, newPolicy)
                    workType = t
                    inlineEditFor = null
                }
            )
        }
    }

    /* ---------------- 근무 수정 시트 ---------------- */
    val curAlba = editingAlba
    val curDate = editingDate
    if (curAlba != null && curDate != null) {
        val (y, m, day) = curDate
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

        ModalBottomSheet(
            sheetState = sheetState,
            onDismissRequest = { editingAlba = null; editingDate = null }
        ) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = {
                    when (step) {
                        is EditStep.List -> { editingAlba = null; editingDate = null }
                        else -> step = EditStep.List
                    }
                }) { Text("‹ 뒤로") }

                Spacer(Modifier.weight(1f))
                Text("${m}월 ${day}일 근무 수정", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.weight(1f))

                if (step is EditStep.List) {
                    TextButton(onClick = {
                        val originalIds = drafts.mapNotNull { it.id }.toSet()
                        val normalized = drafts.sortedWith(compareBy({ it.startH }, { it.startM }))

                        normalized.forEach { dft ->
                            if (dft.id != null) {
                                onUpdateSchedule(
                                    UICalendarSchedule(
                                        id = dft.id,
                                        albaId = curAlba.id,
                                        year = y, month = m, day = day,
                                        startHour = dft.startH, startMinute = dft.startM,
                                        endHour = dft.endH, endMinute = dft.endM,
                                        breakMinutes = dft.breakMin,
                                        overrideHourlyWage = dft.overrideWage
                                    )
                                )
                            }
                        }
                        val remainingIds = normalized.mapNotNull { it.id }.toSet()
                        originalIds.minus(remainingIds).forEach { delId -> onDeleteSchedule(delId) }
                        normalized.filter { it.id == null }.forEach { dft ->
                            onAddSchedule(
                                UICalendarSchedule(
                                    albaId = curAlba.id,
                                    year = y, month = m, day = day,
                                    startHour = dft.startH, startMinute = dft.startM,
                                    endHour = dft.endH, endMinute = dft.endM,
                                    breakMinutes = dft.breakMin,
                                    overrideHourlyWage = dft.overrideWage
                                )
                            )
                        }

                        val forwardCandidate = drafts.withIndex()
                            .filter { iv -> (wageForwardChecked[iv.index] == true) && (iv.value.overrideWage != null) }
                            .minByOrNull { iv -> iv.value.startH * 60 + iv.value.startM }

                        if (forwardCandidate != null) {
                            val seg = forwardCandidate.value
                            onApplyWageForward(curAlba.id, y, m, day, seg.startH * 60 + seg.startM, seg.overrideWage!!)
                        }

                        editingAlba = null; editingDate = null
                    }) { Text("저장") }
                } else {
                    TextButton(onClick = { step = EditStep.List }) { Text("완료") }
                }
            }

            when (val s = step) {
                is EditStep.List -> {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        drafts.forEachIndexed { index, dft ->
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                            ) {
                                Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(curAlba.name, style = MaterialTheme.typography.labelLarge)
                                        Spacer(Modifier.width(8.dp))
                                        Text("유형: 기본", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }

                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("근무시간"); Spacer(Modifier.weight(1f))
                                        TextButton(onClick = { step = EditStep.Time(index) }) {
                                            Text("${fmtAmPm(dft.startH, dft.startM)} ~ ${fmtAmPm(dft.endH, dft.endM)}" +
                                                    if ((dft.endH*60+dft.endM) <= (dft.startH*60+dft.startM)) " (다음날)" else "")
                                        }
                                    }
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("휴게시간"); Spacer(Modifier.weight(1f))
                                        TextButton(onClick = { step = EditStep.Break(index) }) { Text("${dft.breakMin}분") }
                                    }

                                    val isEditing = wageInlineEditing[index] == true
                                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text("그날 시급"); Spacer(Modifier.weight(1f))
                                            if (isEditing) {
                                                var wageText by remember(index) {
                                                    mutableStateOf((dft.overrideWage ?: curAlba.hourlyWage).toString())
                                                }
                                                OutlinedTextField(
                                                    value = wageText,
                                                    onValueChange = {
                                                        val v = it.filter { ch -> ch.isDigit() }.take(9)
                                                        wageText = v
                                                        dft.overrideWage = v.toLongOrNull()
                                                    },
                                                    singleLine = true,
                                                    modifier = Modifier.widthIn(min = 120.dp)
                                                )
                                            } else {
                                                TextButton(onClick = { wageInlineEditing[index] = true }) {
                                                    Text("${(dft.overrideWage ?: curAlba.hourlyWage)}원")
                                                }
                                            }
                                        }
                                        if (isEditing) {
                                            Row(verticalAlignment = Alignment.CenterVertically) {
                                                val checked = wageForwardChecked[index] == true
                                                Checkbox(checked = checked, onCheckedChange = { wageForwardChecked[index] = it })
                                                Spacer(Modifier.width(6.dp))
                                                Text("해당 근무 이후 모두 적용(같은 날 이후 구간 포함)")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                is EditStep.Time -> {
                    val idx = s.index
                    val d = drafts[idx]
                    TimeSheet(
                        startH = d.startH, startM = d.startM, endH = d.endH, endM = d.endM,
                        onDismiss = { step = EditStep.List },
                        onDone = { sh, sm, eh, em ->
                            drafts = drafts.toMutableList().apply {
                                this[idx] = this[idx].copy(startH = sh, startM = sm, endH = eh, endM = em)
                                sortWith(compareBy({ it.startH }, { it.startM }))}
                            step = EditStep.List
                        }
                    )
                }
                is EditStep.Break -> {
                    val idx = s.index
                    val d = drafts[idx]
                    BreakSheet(
                        initial = d.breakMin,
                        onDismiss = { step = EditStep.List },
                        onDone = { mnt ->
                            drafts = drafts.toMutableList().apply { this[idx] = this[idx].copy(breakMin = mnt) }
                            step = EditStep.List
                        }
                    )
                }
            }
        }
    }

    /* -------- 알바 없음 안내 -------- */
    if (showNoAlbaDialog) {
        AlertDialog(
            onDismissRequest = { showNoAlbaDialog = false },
            confirmButton = {
                TextButton(onClick = {
                    showNoAlbaDialog = false
                    onBack()
                }) { Text("확인") }
            },
            title = { Text("알바 등록 필요") },
            text = { Text("근무를 추가하려면 먼저 알바를 등록해 주세요.") }
        )
    }

    /* -------- 겹침 경고 -------- */
    overlapMsg?.let { msg ->
        AlertDialog(
            onDismissRequest = { overlapMsg = null },
            confirmButton = { TextButton(onClick = { overlapMsg = null }) { Text("확인") } },
            title = { Text("추가할 수 없어요") },
            text = { Text(msg) }
        )
    }
}

/* -------------------------------------------------------------------------- */
/* 구성 요소 / 달력 그리드                                                     */
/* -------------------------------------------------------------------------- */

@Composable
private fun ChoiceChip(text: String, color: Color, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected) color.copy(alpha = 0.15f) else MaterialTheme.colorScheme.surfaceVariant
    val fg = if (selected) color else MaterialTheme.colorScheme.onSurface
    Surface(
        modifier = Modifier
            .height(36.dp)
            .clip(RoundedCornerShape(18.dp))
            .clickable { onClick() },
        color = bg, shape = RoundedCornerShape(18.dp)
    ) {
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(RoundedCornerShape(50)).background(color))
            Spacer(Modifier.width(8.dp))
            Text(text, color = fg, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun AlbaChip(name: String, color: Color, checked: Boolean, onToggle: () -> Unit) {
    val bg = if (checked) color.copy(alpha = 0.15f) else MaterialTheme.colorScheme.surfaceVariant
    val fg = if (checked) color else MaterialTheme.colorScheme.onSurface
    Surface(
        modifier = Modifier
            .height(36.dp)
            .clip(RoundedCornerShape(18.dp))
            .clickable { onToggle() },
        color = bg, shape = RoundedCornerShape(18.dp)
    ) {
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(RoundedCornerShape(50)).background(color))
            Spacer(Modifier.width(8.dp))   // ✅ 수정: Modifier.width(...)
            Text(name, color = fg, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun CalendarGrid(
    ym: YearMonthCompat,
    albas: List<UICalendarAlba>,
    activeIds: Set<String>,
    schedules: List<UICalendarSchedule>,
    sundayColor: Color,
    saturdayColor: Color,
    onDayClick: (Int, Int, Int) -> Unit
) {
    val firstCol = firstWeekdayColumn(ym.year, ym.month)
    val dim = daysInMonth(ym.year, ym.month)
    val totalCells = firstCol + dim
    val rows = (totalCells + 6) / 7

    val activeAlbas = remember(albas, activeIds) { albas.filter { it.id in activeIds } }

    Column {
        Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp)) {
            listOf("일", "월", "화", "수", "목", "금", "토").forEachIndexed { i, label ->
                val color = when (i) {
                    0 -> sundayColor
                    6 -> saturdayColor
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                }
                Text(label, modifier = Modifier.weight(1f), textAlign = TextAlign.Center, color = color)
            }
        }
        Spacer(Modifier.height(6.dp))

        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().padding(6.dp)) {
                repeat(rows) { r ->
                    Row(Modifier.fillMaxWidth()) {
                        repeat(7) { c ->
                            val idx = r * 7 + c
                            val day = idx - firstCol + 1
                            if (day in 1..dim) {
                                val dateSchedules = schedules.filter {
                                    it.year == ym.year && it.month == ym.month && it.day == day && it.albaId in activeIds
                                }.sortedWith(compareBy({ it.startHour }, { it.startMinute }))

                                val bars = dateSchedules.take(4).map { s ->
                                    val alba = albas.firstOrNull { it.id == s.albaId }
                                    DayBar(label = alba?.name ?: "알바", color = parseColor(alba?.colorHex ?: "#3B82F6"))
                                }

                                val isPayday = activeAlbas.any { it.payDay == day }
                                val paydayColor = parseColor(activeAlbas.firstOrNull { it.payDay == day }?.colorHex ?: "#000000")

                                val dayTextColor = when (c) {
                                    0 -> sundayColor
                                    6 -> saturdayColor
                                    else -> MaterialTheme.colorScheme.onSurface
                                }

                                DayCell(
                                    day = day,
                                    bars = bars,
                                    isPayday = isPayday,
                                    paydayColor = paydayColor,
                                    hasWork = dateSchedules.isNotEmpty(),
                                    dayTextColor = dayTextColor,
                                    onClick = { onDayClick(ym.year, ym.month, day) },
                                    modifier = Modifier.weight(1f)
                                )
                            } else {
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }
    }
}

private data class DayBar(val label: String, val color: Color)

@Composable
private fun DayCell(
    day: Int,
    bars: List<DayBar>,
    isPayday: Boolean,
    paydayColor: Color,
    hasWork: Boolean,
    dayTextColor: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(10.dp)
    val baseBg = if (hasWork) Color.White else MaterialTheme.colorScheme.surfaceVariant
    val bordered = if (isPayday) Modifier.border(BorderStroke(2.dp, paydayColor), shape) else Modifier

    Surface(
        modifier = modifier.padding(4.dp).then(bordered).clip(shape).clickable { onClick() },
        color = Color.Transparent
    ) {
        Column(Modifier.fillMaxWidth().background(baseBg, shape).padding(8.dp)) {
            Text(day.toString(), color = dayTextColor, fontWeight = if (hasWork) FontWeight.SemiBold else FontWeight.Normal)
            Spacer(Modifier.height(6.dp))
            bars.forEach { bar ->
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(16.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(bar.color.copy(alpha = 0.18f))
                        .padding(horizontal = 6.dp),
                    contentAlignment = Alignment.CenterStart
                ) { Text(bar.label, color = bar.color, style = MaterialTheme.typography.labelSmall) }
                Spacer(Modifier.height(4.dp))
            }
        }
    }
}

/* -------------------------------------------------------------------------- */
/* 유틸/상태 타입                                                              */
/* -------------------------------------------------------------------------- */

private data class YearMonthCompat(val year: Int, val month: Int) {
    fun next() = if (month == 12) copy(year = year + 1, month = 1) else copy(month = month + 1)
    fun prev() = if (month == 1) copy(year = year - 1, month = 12) else copy(month = month - 1)
    companion object {
        fun now(): YearMonthCompat {
            val cal = Calendar.getInstance()
            return YearMonthCompat(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)
        }
    }
}

private fun daysInMonth(year: Int, month: Int): Int {
    val cal = Calendar.getInstance()
    cal.set(Calendar.YEAR, year)
    cal.set(Calendar.MONTH, month - 1)
    return cal.getActualMaximum(Calendar.DAY_OF_MONTH)
}

private fun firstWeekdayColumn(year: Int, month: Int): Int {
    val cal = Calendar.getInstance()
    cal.set(Calendar.YEAR, year)
    cal.set(Calendar.MONTH, month - 1)
    cal.set(Calendar.DAY_OF_MONTH, 1)
    return cal.get(Calendar.DAY_OF_WEEK) - 1
}

private fun parseColor(hex: String?): Color =
    try { Color(android.graphics.Color.parseColor(hex ?: "#3B82F6")) } catch (_: Throwable) { Color(0xFF3B82F6) }

private fun fmtAmPm(h24: Int, m: Int): String {
    val pm = h24 >= 12
    val h12 = ((h24 + 11) % 12) + 1
    return (if (pm) "오후 " else "오전 ") + "%02d:%02d".format(h12, m)
}

/* 편집 시트용 */
private sealed interface EditStep {
    data object List : EditStep
    data class Time(val index: Int) : EditStep
    data class Break(val index: Int) : EditStep
}

private data class SegmentDraft(
    val id: String?,
    var startH: Int,
    var startM: Int,
    var endH: Int,
    var endM: Int,
    var breakMin: Int,
    var overrideWage: Long?
)

/* 가산정책 인라인 팝업 */
@Composable
private fun SurchargeInlineEditor(
    title: String,
    current: SurchargePolicy,
    targetType: UiWorkType,
    onClose: () -> Unit,
    onSave: (SurchargePolicy) -> Unit
) {
    var temp by remember { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when (targetType) {
                    UiWorkType.연장 -> {
                        var txt by remember { mutableStateOf(if (temp.overtimeEnabled) temp.overtimePercent.toString() else "50.0") }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("가산율(%)"); Spacer(Modifier.width(12.dp))
                            OutlinedTextField(
                                value = txt,
                                onValueChange = {
                                    val f = it.filter { ch -> ch.isDigit() || ch == '.' }.take(6)
                                    txt = f
                                    temp = temp.copy(overtimeEnabled = true, overtimePercent = f.toDoubleOrNull() ?: 50.0)
                                },
                                singleLine = true
                            )
                        }
                    }
                    UiWorkType.휴일 -> {
                        var txt by remember { mutableStateOf(if (temp.holidayEnabled) temp.holidayPercent.toString() else "50.0") }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("가산율(%)"); Spacer(Modifier.width(12.dp))
                            OutlinedTextField(
                                value = txt,
                                onValueChange = {
                                    val f = it.filter { ch -> ch.isDigit() || ch == '.' }.take(6)
                                    txt = f
                                    temp = temp.copy(holidayEnabled = true, holidayPercent = f.toDoubleOrNull() ?: 50.0)
                                },
                                singleLine = true
                            )
                        }
                    }
                    UiWorkType.야간 -> {
                        var txt by remember { mutableStateOf(if (temp.nightEnabled) temp.nightPercent.toString() else "50.0") }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("가산율(%)"); Spacer(Modifier.width(12.dp))
                            OutlinedTextField(
                                value = txt,
                                onValueChange = {
                                    val f = it.filter { ch -> ch.isDigit() || ch == '.' }.take(6)
                                    txt = f
                                    temp = temp.copy(nightEnabled = true, nightPercent = f.toDoubleOrNull() ?: 50.0)
                                },
                                singleLine = true
                            )
                        }
                        Text("야간 시간대: 22:00 ~ 06:00 (고정)", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    else -> {}
                }
            }
        },
        confirmButton = { TextButton(onClick = { onSave(temp) }) { Text("저장") } },
        dismissButton = { TextButton(onClick = onClose) { Text("닫기") } }
    )
}

/* --------------------------- 겹침/맞닿음 유틸 --------------------------- */
private fun overlapsStrict(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int): Boolean =
    (aStart < bEnd && bStart < aEnd)

private fun overlapsOrTouch(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int): Boolean =
    (aStart <= bEnd && bStart <= aEnd)
