@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui.alba

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.paycount.app.common.*   // TimeSheet, BreakSheet, DateMultiDialog, WheelCyclic 등
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import androidx.compose.foundation.text.KeyboardOptions

/* ----------------------------- 모델 ----------------------------- */

data class AlbaFormResult(
    val storeName: String,
    val hourlyWage: Long,
    val tax: TaxConfig,
    val insurance: InsuranceConfig,
    val surcharge: SurchargePolicy?,     // 가산 정책(없으면 null)
    val startHour24: Int,
    val startMinute: Int,
    val endHour24: Int,
    val endMinute: Int,
    val breakMinutes: Int,
    val selectedDates: List<LocalDate>,
    val colorHex: String,
    val payDay: Int
)

/* ----------------------------- 화면 ----------------------------- */

@Composable
fun AlbaFormScreen(
    onBack: () -> Unit,
    onSubmit: (AlbaFormResult) -> Unit,
    /** 기존 등록된 모든 스케줄(다른 알바 포함). 겹침 검사용 */
    existingSchedules: List<UICalendarSchedule>
) {
    val ctx = LocalContext.current

    var storeName by remember { mutableStateOf("") }
    var wageDigits by remember { mutableStateOf("") }
    var colorHex by remember { mutableStateOf("#3B82F6") }

    // 색상 팔레트 팝업
    var showPalette by remember { mutableStateOf(false) }

    // 정책 상태
    var taxEnabled by remember { mutableStateOf(false) }
    var taxConfig: TaxConfig by remember { mutableStateOf(TaxConfig.NONE) }

    var insEnabled by remember { mutableStateOf(false) }
    var insuranceConfig: InsuranceConfig by remember { mutableStateOf(InsuranceConfig.NONE) }

    var surchargeEnabled by remember { mutableStateOf(false) }
    var surchargePolicy by remember { mutableStateOf(SurchargePolicy()) }

    // 시간/휴게/날짜/급여일
    var showTimeSheet by remember { mutableStateOf(false) }
    var startHour by remember { mutableStateOf(9) }
    var startMinute by remember { mutableStateOf(0) }
    var endHour by remember { mutableStateOf(18) }
    var endMinute by remember { mutableStateOf(0) }

    var showBreakSheet by remember { mutableStateOf(false) }
    var breakMinutes by remember { mutableStateOf(0) }

    var showDateDialog by remember { mutableStateOf(false) }
    var ym by remember { mutableStateOf(YearMonth.now()) }
    var selectedDates by remember { mutableStateOf(setOf<LocalDate>()) }

    var showPayDaySheet by remember { mutableStateOf(false) }
    var payDay by remember { mutableStateOf(25) }

    // 정책 위자드(아담한 팝업)
    var showPolicyWizard by remember { mutableStateOf(false) }

    var error by remember { mutableStateOf<String?>(null) }

    /* ---------- 겹침 날짜 실시간 계산 ---------- */
    val conflictDates: List<LocalDate> by remember(
        selectedDates, startHour, startMinute, endHour, endMinute, existingSchedules
    ) {
        mutableStateOf(
            run {
                val newStart = startHour * 60 + startMinute
                val newEnd   = endHour * 60 + endMinute
                if (newEnd <= newStart) return@run emptyList() // 시간 자체가 이상하면 겹침은 계산하지 않음
                selectedDates.filter { d ->
                    existingSchedules.any { s ->
                        s.year == d.year && s.month == d.monthValue && s.day == d.dayOfMonth &&
                                overlapsStrict(
                                    newStart, newEnd,
                                    s.startHour * 60 + s.startMinute,
                                    s.endHour * 60 + s.endMinute
                                )
                    }
                }.sorted()
            }
        )
    }

    fun validateAndSubmit() {
        val name = storeName.trim()
        val wageLong = wageDigits.toLongOrNull() ?: 0L
        val newStart = startHour * 60 + startMinute
        val newEnd   = endHour * 60 + endMinute

        when {
            name.isEmpty() -> { error = "매장명을 입력하세요."; return }
            wageLong <= 0L -> { error = "시급을 숫자로 입력하세요."; return }
            newEnd <= newStart -> { error = "근무 종료시간이 시작시간보다 늦어야 합니다."; return }
            selectedDates.isEmpty() -> { error = "근무 날짜를 1개 이상 선택하세요."; return }
            conflictDates.isNotEmpty() -> {
                val sample = conflictDates.take(3).joinToString { "${it.monthValue}월 ${it.dayOfMonth}일" }
                error = "겹치는 근무가 있습니다: $sample"
                Toast.makeText(ctx, error, Toast.LENGTH_SHORT).show()
                return
            }
            payDay !in 1..31 -> { error = "급여일은 1~31일 중에서 선택하세요."; return }
            else -> error = null
        }

        val finalSurcharge =
            if (surchargePolicy.weeklyHolidayEnabled || surchargePolicy.overtimeEnabled ||
                surchargePolicy.holidayEnabled || surchargePolicy.nightEnabled
            ) surchargePolicy else null

        onSubmit(
            AlbaFormResult(
                storeName = name,
                hourlyWage = wageLong,
                tax = if (taxEnabled) taxConfig else TaxConfig.NONE,
                insurance = if (insEnabled) insuranceConfig else InsuranceConfig.NONE,
                surcharge = finalSurcharge,
                startHour24 = startHour, startMinute = startMinute,
                endHour24 = endHour, endMinute = endMinute,
                breakMinutes = breakMinutes,
                selectedDates = selectedDates.toList().sorted(),
                colorHex = colorHex,
                payDay = payDay
            )
        )
        Toast.makeText(ctx, "임시 저장 완료", Toast.LENGTH_SHORT).show()
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("알바 직접 등록") },
                navigationIcon = { TextButton(onClick = onBack) { Text("‹  뒤로") } },
                actions = { TextButton(onClick = { validateAndSubmit() }) { Text("완료") } }
            )
        }
    ) { inner ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            /* 기본 정보 */
            item {
                Text("기본 정보", style = MaterialTheme.typography.titleLarge)
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        OutlinedTextField(
                            value = storeName, onValueChange = { storeName = it },
                            label = { Text("매장명") }, singleLine = true, modifier = Modifier.fillMaxWidth()
                        )
                        OutlinedTextField(
                            value = wageDigits,
                            onValueChange = { s -> wageDigits = s.filter { it.isDigit() }.take(9) },
                            label = { Text("시급(원)") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            visualTransformation = ThousandsTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                        )

                        // ▶ 표시 색상
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("표시 색상", style = MaterialTheme.typography.labelLarge)
                            Spacer(Modifier.weight(1f))
                            Box(
                                modifier = Modifier
                                    .size(32.dp)
                                    .background(parseColor(colorHex), CircleShape)
                                    .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape)
                                    .clickable { showPalette = true }
                            )
                        }

                        // 유효성 메시지
                        if (error != null) {
                            Text(error ?: "", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }

            /* 세금/보험/가산정책 */
            item {
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("세금/보험/가산정책", style = MaterialTheme.typography.titleLarge)
                            Spacer(Modifier.weight(1f))
                            TextButton(onClick = { showPolicyWizard = true }) { Text("설정") }
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(summaryTax(taxEnabled, taxConfig), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(summaryIns(insEnabled, insuranceConfig), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(summarySurcharge(surchargeEnabled, surchargePolicy), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            /* 근무 기본 템플릿 */
            item {
                Text("근무 설정", style = MaterialTheme.typography.titleLarge)
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("근무시간", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showTimeSheet = true }) { Text("시간 선택") }
                        }
                        Text(
                            "선택: ${fmtAmPm(startHour, startMinute)} ~ ${fmtAmPm(endHour, endMinute)}",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (endHour * 60 + endMinute <= startHour * 60 + startMinute) {
                            Text("종료는 시작보다 늦어야 합니다.", color = MaterialTheme.colorScheme.error)
                        }

                        Spacer(Modifier.height(12.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("휴게시간", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showBreakSheet = true }) { Text("설정") }
                        }
                        Text("선택: ${breakMinutes}분", color = MaterialTheme.colorScheme.onSurfaceVariant)

                        Spacer(Modifier.height(12.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("근무 날짜", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showDateDialog = true }) { Text("달력 열기") }
                        }
                        val preview = if (selectedDates.isEmpty()) "선택 없음" else "${selectedDates.size}일 근무"
                        Text("선택: $preview", color = MaterialTheme.colorScheme.onSurfaceVariant)

                        // ⚠️ 겹치는 날짜 경고 표시
                        if (conflictDates.isNotEmpty()) {
                            val sample = conflictDates.take(3).joinToString { "${it.monthValue}월 ${it.dayOfMonth}일" }
                            Text("⚠ 겹치는 날짜: $sample", color = MaterialTheme.colorScheme.error)
                        }

                        Spacer(Modifier.height(12.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("급여 날짜(매달)", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showPayDaySheet = true }) { Text("선택") }
                        }
                        Text("선택: 매월 ${payDay}일", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            item {
                Row(
                    Modifier.fillMaxWidth().padding(bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = onBack) { Text("뒤로") }
                    Spacer(Modifier.weight(1f))
                    Button(
                        onClick = { validateAndSubmit() },
                        enabled = (endHour * 60 + endMinute) > (startHour * 60 + startMinute)
                                && conflictDates.isEmpty()
                    ) { Text("저장") }
                }
            }
        }
    }

    /* ------------------- 색상 팔레트(5 x 3) ------------------- */
    if (showPalette) {
        ColorPaletteDialog(
            initialHex = colorHex,
            onPick = { hex ->
                colorHex = hex
                showPalette = false
            },
            onDismiss = { showPalette = false }
        )
    }

    /* ------------------- 위자드(작은 팝업) ------------------- */
    if (showPolicyWizard) {
        PolicyWizardDialog(
            initialTax = if (taxEnabled) taxConfig else TaxConfig.NONE,
            initialIns = if (insEnabled) insuranceConfig else InsuranceConfig.NONE,
            initialSurcharge = surchargePolicy,
            onDismiss = { showPolicyWizard = false },
            onApply = { t, i, s ->
                taxConfig = t
                taxEnabled = t !is TaxConfig.NONE

                insuranceConfig = i
                insEnabled = i !is InsuranceConfig.NONE

                surchargePolicy = s
                surchargeEnabled = s.weeklyHolidayEnabled || s.overtimeEnabled || s.holidayEnabled || s.nightEnabled

                showPolicyWizard = false
            }
        )
    }

    /* ------------------- 시트/다이얼로그 ------------------- */

    if (showTimeSheet) {
        TimeSheet(
            startH = startHour, startM = startMinute,
            endH = endHour, endM = endMinute,
            onDismiss = { showTimeSheet = false },
            onDone = { sh, sm, eh, em ->
                startHour = sh; startMinute = sm; endHour = eh; endMinute = em
                showTimeSheet = false
            }
        )
    }
    if (showBreakSheet) {
        BreakSheet(
            initial = breakMinutes,
            onDismiss = { showBreakSheet = false },
            onDone = { m -> breakMinutes = m; showBreakSheet = false }
        )
    }
    if (showDateDialog) {
        DateMultiDialog(
            ym = ym,
            selected = selectedDates,
            onYmChange = { ym = it },
            onDismiss = { showDateDialog = false },
            onDone = { set -> selectedDates = set; showDateDialog = false }
        )
    }
    if (showPayDaySheet) {
        PayDaySheet(
            initialDay = payDay,
            onDismiss = { showPayDaySheet = false },
            onDone = { d -> payDay = d; showPayDaySheet = false }
        )
    }
}

/* ----------------------------- 색상 팔레트 다이얼로그 ----------------------------- */

@Composable
private fun ColorPaletteDialog(
    initialHex: String,
    onPick: (String) -> Unit,
    onDismiss: () -> Unit
) {
    // 15개 색상(무지개 + 파스텔)
    val colors = listOf(
        "#EF4444", "#F97316", "#F59E0B", "#EAB308", "#84CC16",
        "#22C55E", "#10B981", "#14B8A6", "#06B6D4", "#0EA5E9",
        "#3B82F6", "#6366F1", "#8B5CF6", "#D946EF", "#F43F5E"
    )

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = true)) {
        Surface(
            modifier = Modifier.widthIn(max = 360.dp).padding(8.dp),
            shape = MaterialTheme.shapes.large,
            tonalElevation = 3.dp
        ) {
            Column(Modifier.padding(16.dp)) {
                Text("색상 선택", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(12.dp))

                // 5개씩 3줄
                colors.chunked(5).forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        row.forEach { hex ->
                            val sel = hex.equals(initialHex, ignoreCase = true)
                            Box(
                                modifier = Modifier
                                    .size(40.dp)
                                    .background(parseColor(hex), CircleShape)
                                    .border(
                                        width = if (sel) 2.dp else 1.dp,
                                        color = if (sel) MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.outline,
                                        shape = CircleShape
                                    )
                                    .clickable { onPick(hex.uppercase()) }
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }

                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("닫기") }
                }
            }
        }
    }
}

/* ----------------------------- 위자드 ----------------------------- */

private enum class WizardStep { TAX, INSURANCE, SURCHARGE }

@Composable
private fun PolicyWizardDialog(
    initialTax: TaxConfig,
    initialIns: InsuranceConfig,
    initialSurcharge: SurchargePolicy,
    onDismiss: () -> Unit,
    onApply: (TaxConfig, InsuranceConfig, SurchargePolicy) -> Unit
) {
    var step by remember { mutableStateOf(WizardStep.TAX) }
    var tax by remember { mutableStateOf(initialTax) }
    var ins by remember { mutableStateOf(initialIns) }
    var sur by remember { mutableStateOf(initialSurcharge) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = true)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 420.dp)
                .padding(8.dp),
            shape = MaterialTheme.shapes.large,
            tonalElevation = 3.dp
        ) {
            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = {
                        when (step) {
                            WizardStep.TAX -> onDismiss()
                            WizardStep.INSURANCE -> step = WizardStep.TAX
                            WizardStep.SURCHARGE -> step = WizardStep.INSURANCE
                        }
                    }) { Text("‹ 뒤로") }
                    Spacer(Modifier.weight(1f))
                    Text("세금/보험/가산정책 설정", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.weight(1f))
                    if (step == WizardStep.SURCHARGE) {
                        TextButton(onClick = { onApply(tax, ins, sur) }) { Text("적용") }
                    } else {
                        TextButton(onClick = {
                            step = when (step) {
                                WizardStep.TAX -> WizardStep.INSURANCE
                                WizardStep.INSURANCE -> WizardStep.SURCHARGE
                                WizardStep.SURCHARGE -> WizardStep.SURCHARGE
                            }
                        }) { Text("다음") }
                    }
                }

                Spacer(Modifier.height(8.dp))

                when (step) {
                    WizardStep.TAX -> TaxEditor(tax) { tax = it }
                    WizardStep.INSURANCE -> InsuranceEditor(ins) { ins = it }
                    WizardStep.SURCHARGE -> SurchargeEditor(
                        current = sur,
                        onChange = { sur = it }
                    )
                }
            }
        }
    }
}

@Composable
private fun TaxEditor(current: TaxConfig, onChange: (TaxConfig) -> Unit) {
    var custom by remember { mutableStateOf(if (current is TaxConfig.CustomPercent) current.percent.toString() else "") }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("세금", style = MaterialTheme.typography.titleMedium)
            SelectableRow("없음", current is TaxConfig.NONE) { onChange(TaxConfig.NONE) }
            SelectableRow("사업소득 3.3%", current is TaxConfig.Biz33) { onChange(TaxConfig.Biz33) }
            SelectableRow("일용직 6.6%", current is TaxConfig.Day66) { onChange(TaxConfig.Day66) }
            SelectableRow("직접 입력(%)", current is TaxConfig.CustomPercent) {
                onChange(TaxConfig.CustomPercent(custom.toDoubleOrNull() ?: 0.0))
            }
            if (current is TaxConfig.CustomPercent) {
                OutlinedTextField(
                    value = custom,
                    onValueChange = {
                        val f = it.filter { ch -> ch.isDigit() || ch == '.' }.take(6)
                        custom = f
                        onChange(TaxConfig.CustomPercent(f.toDoubleOrNull() ?: 0.0))
                    },
                    placeholder = { Text("예: 5.0") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            }
        }
    }
}

@Composable
private fun InsuranceEditor(current: InsuranceConfig, onChange: (InsuranceConfig) -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("보험", style = MaterialTheme.typography.titleMedium)
            SelectableRow("없음", current is InsuranceConfig.NONE) { onChange(InsuranceConfig.NONE) }
            SelectableRow("고용보험만", current is InsuranceConfig.EmploymentOnly) { onChange(InsuranceConfig.EmploymentOnly) }
            SelectableRow("4대보험", current is InsuranceConfig.Four) { onChange(InsuranceConfig.Four) }
        }
    }
}

/* ----------------------------- 가산정책(요구사항 반영) ----------------------------- */

@Composable
private fun SurchargeEditor(current: SurchargePolicy, onChange: (SurchargePolicy) -> Unit) {
    var temp by remember { mutableStateOf(current) }

    fun choiceFrom(enabled: Boolean, pct: Double): String {
        if (!enabled) return "없음"
        val r = pct.roundToInt()
        return when (r) {
            50 -> "50%"
            100 -> "100%"
            else -> "직접 입력"
        }
    }

    var overChoice by remember { mutableStateOf(choiceFrom(temp.overtimeEnabled, temp.overtimePercent)) }
    var holChoice  by remember { mutableStateOf(choiceFrom(temp.holidayEnabled,  temp.holidayPercent)) }
    var nightChoice by remember { mutableStateOf(choiceFrom(temp.nightEnabled,   temp.nightPercent)) }

    var overCustom by remember { mutableStateOf(if (overChoice == "직접 입력") trimPct(temp.overtimePercent) else "") }
    var holCustom  by remember { mutableStateOf(if (holChoice  == "직접 입력") trimPct(temp.holidayPercent)  else "") }
    var nightCustom by remember { mutableStateOf(if (nightChoice == "직접 입력") trimPct(temp.nightPercent) else "") }

    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("가산정책", style = MaterialTheme.typography.titleMedium)

            // 주휴수당 스위치
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("주휴수당")
                Spacer(Modifier.weight(1f))
                Switch(
                    checked = temp.weeklyHolidayEnabled,
                    onCheckedChange = { on ->
                        temp = temp.copy(weeklyHolidayEnabled = on)
                        onChange(temp)
                    }
                )
            }
            Divider()

            // 연장 근무
            PctDropdownRow(
                title = "연장 근무",
                choice = overChoice,
                customText = overCustom,
                onChoice = { ch ->
                    overChoice = ch
                    when (ch) {
                        "없음" -> { temp = temp.copy(overtimeEnabled = false, overtimePercent = 0.0); overCustom = "" }
                        "50%" -> temp = temp.copy(overtimeEnabled = true, overtimePercent = 50.0)
                        "100%" -> temp = temp.copy(overtimeEnabled = true, overtimePercent = 100.0)
                        "직접 입력" -> temp = temp.copy(overtimeEnabled = true)
                    }
                    onChange(temp)
                },
                onCustomChange = { txt ->
                    overCustom = txt
                    val v = txt.toDoubleOrNull()
                    if (overChoice == "직접 입력" && v != null) {
                        temp = temp.copy(overtimeEnabled = true, overtimePercent = v)
                        onChange(temp)
                    }
                }
            )

            // 휴일 근무
            PctDropdownRow(
                title = "휴일 근무",
                choice = holChoice,
                customText = holCustom,
                onChoice = { ch ->
                    holChoice = ch
                    when (ch) {
                        "없음" -> { temp = temp.copy(holidayEnabled = false, holidayPercent = 0.0); holCustom = "" }
                        "50%" -> temp = temp.copy(holidayEnabled = true, holidayPercent = 50.0)
                        "100%" -> temp = temp.copy(holidayEnabled = true, holidayPercent = 100.0)
                        "직접 입력" -> temp = temp.copy(holidayEnabled = true)
                    }
                    onChange(temp)
                },
                onCustomChange = { txt ->
                    holCustom = txt
                    val v = txt.toDoubleOrNull()
                    if (holChoice == "직접 입력" && v != null) {
                        temp = temp.copy(holidayEnabled = true, holidayPercent = v)
                        onChange(temp)
                    }
                }
            )

            // 야간 근무
            PctDropdownRow(
                title = "야간 근무\n(22:00~06:00)",
                choice = nightChoice,
                customText = nightCustom,
                onChoice = { ch ->
                    nightChoice = ch
                    when (ch) {
                        "없음" -> { temp = temp.copy(nightEnabled = false, nightPercent = 0.0); nightCustom = "" }
                        "50%" -> temp = temp.copy(nightEnabled = true, nightPercent = 50.0)
                        "100%" -> temp = temp.copy(nightEnabled = true, nightPercent = 100.0)
                        "직접 입력" -> temp = temp.copy(nightEnabled = true)
                    }
                    onChange(temp)
                },
                onCustomChange = { txt ->
                    nightCustom = txt
                    val v = txt.toDoubleOrNull()
                    if (nightChoice == "직접 입력" && v != null) {
                        temp = temp.copy(nightEnabled = true, nightPercent = v)
                        onChange(temp)
                    }
                }
            )
        }
    }
}

/**
 * 드롭다운 + (필요 시) 같은 칸에서 "직접 입력"을 숫자 입력으로 전환.
 */
@Composable
private fun PctDropdownRow(
    title: String,
    choice: String,
    customText: String,
    onChoice: (String) -> Unit,
    onCustomChange: (String) -> Unit
) {
    val items = listOf("없음", "50%", "100%", "직접 입력")
    var expanded by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(title)
            Spacer(Modifier.weight(1f))

            ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                val readOnly = choice != "직접 입력"
                OutlinedTextField(
                    value = if (readOnly) choice else customText,
                    onValueChange = { s ->
                        if (!readOnly) {
                            val f = s.filter { ch -> ch.isDigit() || ch == '.' }.take(6)
                            onCustomChange(f)
                        }
                    },
                    modifier = Modifier.fillMaxWidth(0.58f),
                    singleLine = true,
                    label = { Text(if (readOnly) "선택" else "가산율(%)") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                    readOnly = readOnly,
                    keyboardOptions = if (readOnly) KeyboardOptions.Default
                    else KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    items.forEach { opt ->
                        DropdownMenuItem(
                            text = { Text(opt) },
                            onClick = {
                                onChoice(opt)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }
    }
}

/* ----------------------------- 공용 ----------------------------- */

@Composable
private fun SelectableRow(text: String, selected: Boolean, onClick: () -> Unit) {
    val color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier.fillMaxWidth().clickable { onClick() }.padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(if (selected) "●" else "○")
        Spacer(Modifier.width(8.dp))
        Text(text, color = color)
    }
}

/* ----------------------------- 요약 텍스트 ----------------------------- */

private fun summaryTax(enabled: Boolean, cfg: TaxConfig): String {
    if (!enabled || cfg is TaxConfig.NONE) return "세금: 없음"
    return "세금: " + when (cfg) {
        TaxConfig.Biz33 -> "사업소득 3.3%"
        TaxConfig.Day66 -> "일용직 6.6%"
        is TaxConfig.CustomPercent -> "직접입력 ${trimPct(cfg.percent)}%"
        TaxConfig.NONE -> "없음"
    }
}

private fun summaryIns(enabled: Boolean, cfg: InsuranceConfig): String {
    if (!enabled || cfg is InsuranceConfig.NONE) return "보험: 없음"
    return "보험: " + when (cfg) {
        InsuranceConfig.EmploymentOnly -> "고용보험만"
        InsuranceConfig.Four -> "4대보험"
        InsuranceConfig.NONE -> "없음"
    }
}

private fun summarySurcharge(enabled: Boolean, s: SurchargePolicy): String {
    if (!enabled) return "가산정책: 없음"
    val list = mutableListOf<String>()
    if (s.weeklyHolidayEnabled) list += "주휴수당"
    if (s.overtimeEnabled) list += "연장 근무 +${trimPct(s.overtimePercent)}%"
    if (s.holidayEnabled) list += "휴일 근무 +${trimPct(s.holidayPercent)}%"
    if (s.nightEnabled) list += "야간 근무 +${trimPct(s.nightPercent)}%"
    return "가산정책: " + if (list.isEmpty()) "없음" else list.joinToString(", ")
}

/* ----------------------------- PayDaySheet ----------------------------- */

@Composable
private fun PayDaySheet(
    initialDay: Int,
    onDismiss: () -> Unit,
    onDone: (Int) -> Unit
) {
    var day by remember { mutableStateOf(initialDay.coerceIn(1, 31)) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onDismiss) { Text("‹ 뒤로") }
            Spacer(Modifier.weight(1f))
            Text("급여 지급 날짜(매달)", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { onDone(day) }) { Text("완료") }
        }
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            WheelCyclic(
                items = (1..31).map { "${it}일" },
                selectedIndex = day - 1,
                onSelected = { idx -> day = (idx + 1).coerceIn(1, 31) },
                widthDp = 96, visibleCount = 3, rowHeight = 40.dp
            )
            Spacer(Modifier.height(8.dp))
            Text("선택: 매월 ${day}일", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
        }
    }
}

/* ----------------------------- 유틸 ----------------------------- */

private class ThousandsTransformation : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val digits = text.text.filter { it.isDigit() }
        if (digits.isEmpty()) return TransformedText(AnnotatedString(""), OffsetMapping.Identity)
        val (transformed, mapping) = mapDigits(digits)
        return TransformedText(AnnotatedString(transformed), mapping)
    }
    private fun mapDigits(src: String): Pair<String, OffsetMapping> {
        val n = src.length
        val firstGroup = if (n % 3 == 0) 3 else n % 3
        val sb = StringBuilder()
        val o2t = IntArray(n + 1)
        var w = 0
        o2t[0] = 0
        for (i in 0 until n) {
            sb.append(src[i]); w++
            val needComma = (i != n - 1) && ((i + 1 == firstGroup) || ((i + 1 - firstGroup) % 3 == 0))
            if (needComma) { sb.append(','); w++ }
            o2t[i + 1] = w
        }
        val t = sb.toString()
        val t2o = IntArray(t.length + 1)
        var cnt = 0
        for (i in t.indices) { if (t[i] != ',') cnt++; t2o[i + 1] = cnt }
        val map = object : OffsetMapping {
            override fun originalToTransformed(offset: Int) = o2t[min(max(0, offset), src.length)]
            override fun transformedToOriginal(offset: Int) = t2o[min(max(0, offset), t.length)]
        }
        return t to map
    }
}

private fun fmtAmPm(h24: Int, m: Int): String {
    val pm = h24 >= 12
    val h12 = ((h24 + 11) % 12) + 1
    return (if (pm) "오후 " else "오전 ") + "%02d:%02d".format(h12, m)
}

private fun trimPct(p: Double): String {
    val i = p.toInt()
    return if (i.toDouble() == p) i.toString() else p.toString()
}

private fun parseColor(hex: String): Color = try {
    Color(android.graphics.Color.parseColor(hex))
} catch (_: Throwable) {
    Color(0xFF3B82F6) // fallback
}

/* ---- 겹침 판정: 맞닿는 건 허용(= OK), 진짜로 겹치면 true ---- */
private fun overlapsStrict(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int): Boolean =
    (aStart < bEnd && bStart < aEnd)
