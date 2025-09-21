@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui.alba

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.runtime.derivedStateOf

/* ----------------------------- 결과/프리필 모델 ----------------------------- */

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

/** 폼 프리필용(수정 진입 시 사용) */
data class AlbaFormInitial(
    val storeName: String,
    val hourlyWage: Long,
    val tax: TaxConfig = TaxConfig.NONE,
    val insurance: InsuranceConfig = InsuranceConfig.NONE,
    val surcharge: SurchargePolicy? = null,
    val startHour24: Int = 9,
    val startMinute: Int = 0,
    val endHour24: Int = 18,
    val endMinute: Int = 0,
    val breakMinutes: Int = 0,
    val selectedDates: Set<LocalDate> = emptySet(),
    val colorHex: String = "#3B82F6",
    val payDay: Int = 25
)

/* ----------------------------- 화면 ----------------------------- */

@Composable
fun AlbaFormScreen(
    onBack: () -> Unit,
    onSubmit: (AlbaFormResult) -> Unit,
    existingSchedules: List<UICalendarSchedule>,   // 겹침 검사
    initial: AlbaFormInitial? = null               // 프리필(null이면 신규)
) {
    val ctx = LocalContext.current
    val isEditMode = initial != null

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

    // ✅ “앱을 여는 날 기준”으로 달력을 엽니다.
    var ym by remember { mutableStateOf(YearMonth.now()) }

    var selectedDates by remember { mutableStateOf(setOf<LocalDate>()) }

    var showPayDaySheet by remember { mutableStateOf(false) }
    var payDay by remember { mutableStateOf(25) }

    // 정책 위자드(아담한 팝업)
    var showPolicyWizard by remember { mutableStateOf(false) }

    var error by remember { mutableStateOf<String?>(null) }

    /* ---------- 프리필 적용 ---------- */
    LaunchedEffect(initial) {
        initial?.let { i ->
            storeName = i.storeName
            wageDigits = i.hourlyWage.toString()
            colorHex = i.colorHex

            taxConfig = i.tax;     taxEnabled = i.tax !is TaxConfig.NONE
            insuranceConfig = i.insurance; insEnabled = i.insurance !is InsuranceConfig.NONE
            surchargePolicy = i.surcharge ?: SurchargePolicy()
            surchargeEnabled = i.surcharge != null

            startHour = i.startHour24; startMinute = i.startMinute
            endHour = i.endHour24; endMinute = i.endMinute
            breakMinutes = i.breakMinutes

            selectedDates = i.selectedDates
            payDay = i.payDay

            // ✅ 폼은 항상 "현재 월"에서 시작. (요청사항)
            ym = YearMonth.now()
        }
    }

    /* ---------- 겹침 검사 ---------- */
    val conflictDates by remember(
        selectedDates, startHour, startMinute, endHour, endMinute, existingSchedules
    ) {
        derivedStateOf<List<LocalDate>> {
            if (selectedDates.isEmpty()) emptyList()
            else {
                val sMin0 = startHour * 60 + startMinute
                var eMin0 = endHour * 60 + endMinute
                val isOvernight = eMin0 <= sMin0
                if (isOvernight) eMin0 += 24 * 60

                selectedDates.filter { d ->
                    fun conflicts(list: List<UICalendarSchedule>, dayOffset: Int): Boolean =
                        list.any { sc ->
                            var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60
                            var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60
                            if (b <= a) b += 24 * 60
                            (sMin0 < b) && (a < eMin0)
                        }

                    val nextD = d.plusDays(1)
                    val prevD = d.minusDays(1)

                    val same = existingSchedules.filter {
                        it.year == d.year && it.month == d.monthValue && it.day == d.dayOfMonth
                    }
                    val next = existingSchedules.filter {
                        it.year == nextD.year && it.month == nextD.monthValue && it.day == nextD.dayOfMonth
                    }
                    val prev = existingSchedules.filter {
                        it.year == prevD.year && it.month == prevD.monthValue && it.day == prevD.dayOfMonth
                    }

                    conflicts(same, 0) || conflicts(prev, -1) || conflicts(next, +1)
                }.sorted()
            }
        }
    }

    fun validateAndSubmit() {
        val name = storeName.trim()
        val wageLong = wageDigits.toLongOrNull() ?: 0L

        // ✅ 수정 모드에서는 날짜를 건드리지 않아도 저장 가능
        val needDates = initial == null || selectedDates.isNotEmpty()

        when {
            name.isEmpty() -> { error = "매장명을 입력하세요."; return }
            wageLong <= 0L -> { error = "시급을 숫자로 입력하세요."; return }
            !needDates -> error = null
            selectedDates.isEmpty() -> { error = "근무 날짜를 1개 이상 선택하세요."; return }
            payDay !in 1..31 -> { error = "급여일은 1~31일 중에서 선택하세요."; return }
            conflictDates.isNotEmpty() -> {
                error = "겹치는 날짜가 있습니다. 아래 경고를 확인해 주세요."
                Toast.makeText(ctx, "겹치는 근무가 있는 날짜가 있어 저장할 수 없어요.", Toast.LENGTH_SHORT).show()
                return
            }
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
        Toast.makeText(ctx, if (isEditMode) "수정 사항을 저장했어요" else "임시 저장 완료", Toast.LENGTH_SHORT).show()
    }

    /* ---------------- UI ---------------- */
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(if (isEditMode) "알바 수정" else "알바 등록") },
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

                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { showPalette = true }
                        ) {
                            Text("표시 색상", style = MaterialTheme.typography.labelLarge)
                            Spacer(Modifier.weight(1f))
                            Box(
                                modifier = Modifier
                                    .size(32.dp)
                                    .background(parseColor(colorHex), CircleShape)
                                    .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape)
                            )
                        }

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

            /* 근무 설정 */
            item {
                Text("근무 설정", style = MaterialTheme.typography.titleLarge)
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("근무시간", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showTimeSheet = true }) { Text("시간 선택") }
                        }
                        val overnight = (endHour * 60 + endMinute) <= (startHour * 60 + startMinute)
                        Text(
                            "선택: ${fmtAmPm(startHour, startMinute)} ~ ${fmtAmPm(endHour, endMinute)}" +
                                    if (overnight) " (다음날)" else "",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

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
                        val preview = if (selectedDates.isEmpty()) "선택 없음"
                        else "${selectedDates.size}일 근무"
                        Text("선택: $preview", color = MaterialTheme.colorScheme.onSurfaceVariant)

                        if (conflictDates.isNotEmpty()) {
                            val msg = conflictDates.joinToString { "${it.monthValue}/${it.dayOfMonth}" }
                            Spacer(Modifier.height(6.dp))
                            Text("⚠ 겹치는 날짜: $msg", color = MaterialTheme.colorScheme.error)
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
                    Button(onClick = { validateAndSubmit() }) { Text("저장") }
                }
            }
        }
    }

    /* -------- 팝업들 -------- */
    if (showPalette) {
        ColorPaletteDialog(
            initialHex = colorHex,
            onPick = { hex -> colorHex = hex; showPalette = false },
            onDismiss = { showPalette = false }
        )
    }

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
                surchargeEnabled =
                    s.weeklyHolidayEnabled || s.overtimeEnabled || s.holidayEnabled || s.nightEnabled
                showPolicyWizard = false
            }
        )
    }

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
        // ✅ 항상 현재 월로 시작하지만, 사용자가 월을 바꾸면 ym 상태에 저장되어 유지됩니다.
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

                colors.chunked(5).forEach { row ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
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

/* ----------------------------- 위자드(세금/보험/가산) ----------------------------- */

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

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = true)) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 420.dp)
                .padding(8.dp),
            shape = MaterialTheme.shapes.large,
            tonalElevation = 3.dp
        ) {
            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
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
                    WizardStep.SURCHARGE -> SurchargeEditor(current = sur) { sur = it }
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

/* ----------------------------- 가산정책 에디터 ----------------------------- */

@Composable
private fun SurchargeEditor(current: SurchargePolicy, onChange: (SurchargePolicy) -> Unit) {
    var temp by remember { mutableStateOf(current) }

    fun choiceFrom(enabled: Boolean, pct: Double): String {
        if (!enabled) return "없음"
        val r = pct.roundToInt()
        return when (r) { 50 -> "50%"; 100 -> "100%"; else -> "직접 입력" }
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
            HorizontalDivider()

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

/* ----------------------------- 공용 컴포넌트/요약 ----------------------------- */

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
                            onClick = { onChoice(opt); expanded = false }
                        )
                    }
                }
            }
        }
    }
}

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
