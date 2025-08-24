@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui.alba

import android.icu.text.DecimalFormat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.paycount.app.common.BreakSheet
import com.paycount.app.common.TimeSheet
import java.util.Calendar
import kotlin.math.max

/* ---------- 편집 스텝 ---------- */
private sealed interface EditStep {
    data object List : EditStep
    data class Time(val index: Int) : EditStep
    data class Break(val index: Int) : EditStep
}

/* ---------- 에디터 초안 ---------- */
private data class SegmentDraft(
    val id: String?,                // 기존이면 id, 새로 추가면 null
    var startH: Int,
    var startM: Int,
    var endH: Int,
    var endM: Int,
    var breakMin: Int,
    var overrideWage: Long?         // null = 기본 시급 사용
)

/* -------------------------------------------------------------------------- */
/* 달력 화면                                                                  */
/* -------------------------------------------------------------------------- */

@Composable
fun CalendarScreen(
    onBack: () -> Unit,
    albas: List<UICalendarAlba>,
    schedules: List<UICalendarSchedule>,

    onDeleteSchedule: (String) -> Unit,
    onUpdateSchedule: (UICalendarSchedule) -> Unit,

    // ‘해당 근무 시작시각(분)’ 부터 적용
    onApplyWageForward: (
        albaId: String,
        effectiveY: Int, effectiveM: Int, effectiveD: Int,
        effectiveStartMinutes: Int,
        newWage: Long
    ) -> Unit,

    // 새 구간 추가
    onAddSchedule: (UICalendarSchedule) -> Unit
) {
    var ym by remember { mutableStateOf(YearMonthCompat.now()) }
    var activeIds by remember { mutableStateOf(albas.map { it.id }.toSet()) }
    var sheetDay by remember { mutableStateOf<Triple<Int, Int, Int>?>(null) }

    // 편집용 상태
    var editingAlba by remember { mutableStateOf<UICalendarAlba?>(null) }
    var editingDate by remember { mutableStateOf<Triple<Int, Int, Int>?>(null) }
    var drafts by remember { mutableStateOf(listOf<SegmentDraft>()) }
    var step by remember { mutableStateOf<EditStep>(EditStep.List) }

    // 인라인 임금 편집용(해당 근무 이후 적용)
    val wageInlineEditing = remember { mutableStateMapOf<Int, Boolean>() }      // index -> isEditing
    val wageForwardChecked = remember { mutableStateMapOf<Int, Boolean>() }     // index -> apply forward

    // 근무 추가 시트
    var showAddSheet by remember { mutableStateOf(false) }
    var addDate by remember { mutableStateOf<Triple<Int, Int, Int>?>(null) }

    // 알바 없음 안내 다이얼로그
    var showNoAlbaDialog by remember { mutableStateOf(false) }

    val df = remember { DecimalFormat("#,###") }
    val monthTotal by remember(ym, activeIds, schedules, albas) {
        mutableStateOf(calcMonthTotal(ym, schedules, albas.associateBy { it.id }, activeIds))
    }

    val sundayColor = Color(0xFFE53935)
    val saturdayColor = Color(0xFF1E88E5)

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
            Modifier.fillMaxSize().padding(inner).padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "이달 예상 합계",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.width(12.dp))
                    Text("${df.format(monthTotal)}원", fontWeight = FontWeight.Bold)
                }
            }

            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically
            ) {
                albas.forEach { a ->
                    val on = a.id in activeIds
                    AlbaChip(
                        name = a.name,
                        color = parseColor(a.colorHex),
                        checked = on,
                        onToggle = {
                            activeIds = activeIds.toMutableSet().apply {
                                if (on) remove(a.id) else add(a.id)
                            }
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
                    // 상단 우측 "근무 추가"
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

                        val totalPay = list.sumOf { s ->
                            val wage = s.overrideHourlyWage ?: alba.hourlyWage
                            (paidMinutes(s) / 60.0 * wage).toLong()
                        }

                        // 흰 배경, 심플 카드
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
                                    Text("${df.format(totalPay)}원", fontWeight = FontWeight.Bold)
                                }
                                Spacer(Modifier.height(6.dp))

                                list.forEach { s ->
                                    Text("• ${fmtAmPm(s.startHour, s.startMinute)} ~ ${fmtAmPm(s.endHour, s.endMinute)}  (휴게 ${s.breakMinutes}분)")
                                }

                                Spacer(Modifier.height(10.dp))
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    OutlinedButton(
                                        onClick = { onDeleteSchedule(list.last().id) },
                                        modifier = Modifier.weight(1f)
                                    ) { Text("삭제(마지막 구간)") }

                                    Button(
                                        onClick = {
                                            // 편집 시트 열기
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
                                            // 인라인 편집 상태 초기화
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
        var sH by remember(addTriple) { mutableStateOf(9) }
        var sM by remember(addTriple) { mutableStateOf(0) }
        var eH by remember(addTriple) { mutableStateOf(18) }
        var eM by remember(addTriple) { mutableStateOf(0) }
        var br by remember(addTriple) { mutableStateOf(0) }

        // 시급: 텍스트 → 탭 → 입력
        var wageEditing by remember(addTriple) { mutableStateOf(false) }
        var wageText by remember(addTriple) { mutableStateOf("") }

        val selectedAlba = albas.firstOrNull { it.id == selectedAlbaId }

        // 알바 선택 시 기본 시급 세팅(입력 중이 아니면)
        LaunchedEffect(selectedAlbaId) {
            if (!wageEditing) {
                wageText = selectedAlba?.hourlyWage?.toString() ?: ""
            }
        }

        // 픽커 토글
        var showTimePicker by remember { mutableStateOf(false) }
        var showBreakPicker by remember { mutableStateOf(false) }

        ModalBottomSheet(onDismissRequest = { showAddSheet = false }) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // 상단 바
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { showAddSheet = false }) { Text("‹ 뒤로") }
                    Spacer(Modifier.weight(1f))
                    Text("${y}년 ${m}월 ${day}일 근무 추가", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.weight(1f))
                }

                Text("어떤 알바인가요?", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.horizontalScroll(rememberScrollState())) {
                    albas.forEach { a ->
                        ChoiceChip(
                            text = a.name,
                            color = parseColor(a.colorHex),
                            selected = a.id == selectedAlbaId,
                            onClick = {
                                selectedAlbaId = a.id
                                if (!wageEditing) wageText = a.hourlyWage.toString()
                            }
                        )
                        Spacer(Modifier.width(8.dp))
                    }
                }

                Divider()

                // 근무 시간
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("근무 시간")
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { showTimePicker = true }) {
                        Text("${fmtAmPm(sH, sM)} ~ ${fmtAmPm(eH, eM)}")
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

                // 시급(텍스트 → 탭 → 입력)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("시급", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (wageEditing) {
                        OutlinedTextField(
                            value = wageText,
                            onValueChange = { wageText = it.filter { ch -> ch.isDigit() }.take(9) },
                            singleLine = true,
                            placeholder = { Text("알바 선택 후 기본 시급 적용") },
                            modifier = Modifier.fillMaxWidth()
                        )
                    } else {
                        TextButton(
                            onClick = { wageEditing = true },
                            modifier = Modifier.align(Alignment.End)
                        ) { Text(if (wageText.isBlank()) "—" else "${wageText}원") }
                    }
                }

                Spacer(Modifier.height(4.dp))

                Button(
                    onClick = {
                        val alba = selectedAlba ?: return@Button
                        val typed = wageText.toLongOrNull()
                        val override = if (typed != null && typed != alba.hourlyWage) typed else null
                        onAddSchedule(
                            UICalendarSchedule(
                                id = makeId(),
                                albaId = alba.id,
                                year = y, month = m, day = day,
                                startHour = sH, startMinute = sM,
                                endHour = eH, endMinute = eM,
                                breakMinutes = br,
                                overrideHourlyWage = override
                            )
                        )
                        showAddSheet = false
                    },
                    enabled = selectedAlbaId != null,
                    modifier = Modifier.fillMaxWidth()
                ) { Text("저장하기") }
            }
        }
    }

    /* ---------------- 근무 수정 시트(스텝 전환) ---------------- */
    val curAlba = editingAlba
    val curDate = editingDate
    if (curAlba != null && curDate != null) {
        val (y, m, day) = curDate
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

        ModalBottomSheet(
            sheetState = sheetState,
            onDismissRequest = { editingAlba = null; editingDate = null }
        ) {
            // 상단 바
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
                        // 저장: update / delete / add
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
                                    id = makeId(),
                                    albaId = curAlba.id,
                                    year = y, month = m, day = day,
                                    startHour = dft.startH, startMinute = dft.startM,
                                    endHour = dft.endH, endMinute = dft.endM,
                                    breakMinutes = dft.breakMin,
                                    overrideHourlyWage = dft.overrideWage
                                )
                            )
                        }

                        // ‘해당 근무 이후’ 체크된 항목 중 가장 이른 시작시각 1건 적용
                        val forwardCandidate = drafts.withIndex()
                            .filter { iv -> (wageForwardChecked[iv.index] == true) && (iv.value.overrideWage != null) }
                            .minByOrNull { iv -> iv.value.startH * 60 + iv.value.startM }

                        if (forwardCandidate != null) {
                            val seg = forwardCandidate.value
                            onApplyWageForward(
                                curAlba.id, y, m, day,
                                seg.startH * 60 + seg.startM,
                                seg.overrideWage!!
                            )
                        }

                        editingAlba = null; editingDate = null
                    }) { Text("저장") }
                } else {
                    TextButton(onClick = { step = EditStep.List }) { Text("완료") }
                }
            }

            // 본문
            when (val s = step) {
                is EditStep.List -> {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        // + 시간 추가
                        OutlinedButton(
                            onClick = {
                                val base = drafts.lastOrNull()
                                val new = if (base != null) base.copy(id = null) else SegmentDraft(null, 9, 0, 13, 0, 0, null)
                                drafts = (drafts + new).sortedWith(compareBy({ it.startH }, { it.startM }))
                                val newIndex = drafts.indexOf(new)
                                wageInlineEditing[newIndex] = false
                                wageForwardChecked[newIndex] = false
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("+ 시간 추가") }

                        drafts.forEachIndexed { index, dft ->
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                            ) {
                                Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text("구간 ${index + 1}", style = MaterialTheme.typography.labelLarge)

                                    // 근무시간
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("근무시간")
                                        Spacer(Modifier.weight(1f))
                                        TextButton(onClick = { step = EditStep.Time(index) }) {
                                            Text("${fmtAmPm(dft.startH, dft.startM)} ~ ${fmtAmPm(dft.endH, dft.endM)}")
                                        }
                                    }
                                    // 휴게시간
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("휴게시간")
                                        Spacer(Modifier.weight(1f))
                                        TextButton(onClick = { step = EditStep.Break(index) }) { Text("${dft.breakMin}분") }
                                    }

                                    // 그날 시급(텍스트 → 탭 → 인라인 입력)
                                    val isEditing = wageInlineEditing[index] == true
                                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text("그날 시급")
                                            Spacer(Modifier.weight(1f))
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
                                                Checkbox(
                                                    checked = checked,
                                                    onCheckedChange = { wageForwardChecked[index] = it }
                                                )
                                                Spacer(Modifier.width(6.dp))
                                                Text("해당 근무 이후 모두 적용(같은 날 이후 구간 포함)")
                                            }
                                        }
                                    }

                                    // 카드 내부 삭제
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                                        TextButton(
                                            onClick = {
                                                drafts = drafts.toMutableList().also { it.removeAt(index) }
                                                wageInlineEditing.remove(index)
                                                wageForwardChecked.remove(index)
                                                if (drafts.isEmpty()) {
                                                    drafts = listOf(SegmentDraft(null, 9, 0, 13, 0, 0, null))
                                                    wageInlineEditing[0] = false
                                                    wageForwardChecked[0] = false
                                                }
                                            }
                                        ) { Text("삭제") }
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
                                sortWith(compareBy({ it.startH }, { it.startM }))
                            }
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
                    // 메인(시작) 화면으로 이동
                    onBack()
                }) { Text("확인") }
            },
            title = { Text("알바 등록 필요") },
            text = { Text("근무를 추가하려면 먼저 알바를 등록해 주세요.") }
        )
    }
}

/* -------------------------------------------------------------------------- */
/* 구성요소 / 달력 그리드                                                      */
/* -------------------------------------------------------------------------- */

@Composable
private fun ChoiceChip(text: String, color: Color, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected) color.copy(alpha = 0.15f) else MaterialTheme.colorScheme.surfaceVariant
    val fg = if (selected) color else MaterialTheme.colorScheme.onSurface
    Surface(
        modifier = Modifier.height(36.dp).clip(RoundedCornerShape(18.dp)).clickable { onClick() },
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
        modifier = Modifier.height(36.dp).clip(RoundedCornerShape(18.dp)).clickable { onToggle() },
        color = bg, shape = RoundedCornerShape(18.dp)
    ) {
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(RoundedCornerShape(50)).background(color))
            Spacer(Modifier.width(8.dp))
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
            listOf("일","월","화","수","목","금","토").forEachIndexed { i, label ->
                val color = when (i) { 0 -> sundayColor; 6 -> saturdayColor; else -> MaterialTheme.colorScheme.onSurfaceVariant }
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
                                    it.year == ym.year && it.month == ym.month &&
                                            it.day == day && it.albaId in activeIds
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

    Surface(
        modifier = modifier.padding(4.dp).clip(shape).clickable { onClick() },
        color = Color.Transparent,
        border = if (isPayday) BorderStroke(2.dp, paydayColor) else null
    ) {
        Column(Modifier.fillMaxWidth().background(baseBg, shape).padding(8.dp)) {
            Text(day.toString(), color = dayTextColor, fontWeight = if (hasWork) FontWeight.SemiBold else FontWeight.Normal)
            Spacer(Modifier.height(6.dp))
            bars.forEach { bar ->
                Box(
                    Modifier.fillMaxWidth().height(16.dp).clip(RoundedCornerShape(6.dp))
                        .background(bar.color.copy(alpha = 0.18f)).padding(horizontal = 6.dp),
                    contentAlignment = Alignment.CenterStart
                ) { Text(bar.label, color = bar.color, style = MaterialTheme.typography.labelSmall) }
                Spacer(Modifier.height(4.dp))
            }
        }
    }
}

/* -------------------------------------------------------------------------- */
/* 유틸                                                                       */
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
private fun parseColor(hex: String): Color =
    try { Color(android.graphics.Color.parseColor(hex)) } catch (_: Throwable) { Color(0xFF3B82F6) }

private fun fmtAmPm(h24: Int, m: Int): String {
    val pm = h24 >= 12
    val h12 = ((h24 + 11) % 12) + 1
    return (if (pm) "오후 " else "오전 ") + "%02d:%02d".format(h12, m)
}

private fun paidMinutes(s: UICalendarSchedule): Int {
    val start = s.startHour * 60 + s.startMinute
    val end = s.endHour * 60 + s.endMinute
    val total = max(0, end - start)
    return max(0, total - s.breakMinutes)
}

private fun calcMonthTotal(
    ym: YearMonthCompat,
    schedules: List<UICalendarSchedule>,
    albas: Map<String, UICalendarAlba>,
    activeIds: Set<String>
): Long {
    var sum = 0L
    schedules.forEach { s ->
        if (s.year == ym.year && s.month == ym.month && s.albaId in activeIds) {
            val alba = albas[s.albaId] ?: return@forEach
            val wage = s.overrideHourlyWage ?: alba.hourlyWage
            val mins = paidMinutes(s)
            sum += (mins / 60.0 * wage).toLong()
        }
    }
    return sum
}

private fun makeId() = System.nanoTime().toString()
