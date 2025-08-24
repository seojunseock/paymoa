@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui.alba

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.paycount.app.common.* // ← 공용 피커(시간/날짜/휴게/휠) 전부 여기서 import
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.max
import kotlin.math.min

/* ----------------------------- 결과/설정 모델 ----------------------------- */
data class AlbaFormResult(
    val storeName: String,
    val hourlyWage: Long,
    val tax: TaxConfig,
    val insurance: InsuranceConfig,
    val startHour24: Int,
    val startMinute: Int,
    val endHour24: Int,
    val endMinute: Int,
    val breakMinutes: Int,
    val selectedDates: List<LocalDate>,
    val colorHex: String,
    val payDay: Int
)

sealed interface TaxConfig {
    data object NONE : TaxConfig
    data object DAY_6_6 : TaxConfig
    data object BIZ_3_3 : TaxConfig
    data object WAGE_TABLE : TaxConfig
    data class CUSTOM_PERCENT(val percent: Double) : TaxConfig
}

sealed interface InsuranceConfig {
    data object NONE : InsuranceConfig
    data object EMPLOYMENT_ONLY : InsuranceConfig
    data object FOUR : InsuranceConfig
}

/* ----------------------------- 화면 ----------------------------- */
@Composable
fun AlbaFormScreen(
    onBack: () -> Unit,
    onSubmit: (AlbaFormResult) -> Unit
) {
    val ctx = LocalContext.current

    var storeName by remember { mutableStateOf("") }
    var wageDigits by remember { mutableStateOf("") } // 숫자만 저장
    var colorHex by remember { mutableStateOf("#3B82F6") }

    var taxEnabled by remember { mutableStateOf(false) }
    var taxConfig: TaxConfig by remember { mutableStateOf(TaxConfig.NONE) }
    var showTaxSheet by remember { mutableStateOf(false) }

    var insEnabled by remember { mutableStateOf(false) }
    var insuranceConfig: InsuranceConfig by remember { mutableStateOf(InsuranceConfig.NONE) }
    var showInsSheet by remember { mutableStateOf(false) }

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

    var error by remember { mutableStateOf<String?>(null) }

    fun validateAndSubmit() {
        val name = storeName.trim()
        val wageLong = wageDigits.toLongOrNull() ?: 0L
        val color = colorHex.trim()
        when {
            name.isEmpty() -> { error = "매장명을 입력하세요."; return }
            wageLong <= 0L -> { error = "시급을 숫자로 입력하세요."; return }
            !(color.startsWith("#") && (color.length == 7 || color.length == 4)) -> {
                error = "색상은 #RRGGBB 형식으로 입력하세요."; return
            }
            selectedDates.isEmpty() -> { error = "근무 날짜를 1개 이상 선택하세요."; return }
            payDay !in 1..31 -> { error = "급여일은 1~31일 중에서 선택하세요."; return }
            else -> error = null
        }
        onSubmit(
            AlbaFormResult(
                storeName = name,
                hourlyWage = wageLong,
                tax = if (taxEnabled) taxConfig else TaxConfig.NONE,
                insurance = if (insEnabled) insuranceConfig else InsuranceConfig.NONE,
                startHour24 = startHour, startMinute = startMinute,
                endHour24 = endHour, endMinute = endMinute,
                breakMinutes = breakMinutes,
                selectedDates = selectedDates.toList().sorted(),
                colorHex = color,
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
            modifier = Modifier.fillMaxSize().padding(inner).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            /* 기본 정보 */
            item {
                Text("기본 정보", style = MaterialTheme.typography.titleLarge)
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
                            visualTransformation = ThousandsTransformation()
                        )
                        OutlinedTextField(
                            value = colorHex,
                            onValueChange = { s ->
                                val up = s.uppercase()
                                val filtered = up.filterIndexed { idx, ch ->
                                    if (idx == 0) ch == '#' else ch.isDigit() || ch in 'A'..'F'
                                }
                                colorHex = ("#" + filtered.dropWhile { it == '#' }).take(7)
                            },
                            label = { Text("표시 색상 (#RRGGBB)") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                        if (error != null) Text(error ?: "", color = MaterialTheme.colorScheme.error)
                    }
                }
            }

            /* 세금/보험 */
            item {
                Text("세금/보험", style = MaterialTheme.typography.titleLarge)
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("세금", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Switch(
                                checked = taxEnabled,
                                onCheckedChange = { on ->
                                    if (on) { if (taxConfig == TaxConfig.NONE) showTaxSheet = true; taxEnabled = true }
                                    else { taxEnabled = false; taxConfig = TaxConfig.NONE }
                                }
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "현재: " + when (taxConfig) {
                                    TaxConfig.NONE -> "없음"
                                    TaxConfig.DAY_6_6 -> "일용직 6.6%"
                                    TaxConfig.BIZ_3_3 -> "사업소득 3.3%"
                                    TaxConfig.WAGE_TABLE -> "근로소득 간이세액표"
                                    is TaxConfig.CUSTOM_PERCENT -> "직접입력 ${(taxConfig as TaxConfig.CUSTOM_PERCENT).percent}%"
                                },
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showTaxSheet = true }) { Text("세금 설정") }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("보험", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Switch(
                                checked = insEnabled,
                                onCheckedChange = { on ->
                                    if (on) { if (insuranceConfig == InsuranceConfig.NONE) showInsSheet = true; insEnabled = true }
                                    else { insEnabled = false; insuranceConfig = InsuranceConfig.NONE }
                                }
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "현재: " + when (insuranceConfig) {
                                    InsuranceConfig.NONE -> "미가입"
                                    InsuranceConfig.EMPLOYMENT_ONLY -> "고용보험만"
                                    InsuranceConfig.FOUR -> "4대보험"
                                },
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showInsSheet = true }) { Text("보험 설정") }
                        }
                    }
                }
            }

            /* 근무 설정 */
            item {
                Text("근무 설정", style = MaterialTheme.typography.titleLarge)
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        // 근무시간
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("근무시간", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showTimeSheet = true }) { Text("시간 선택") }
                        }
                        Text(
                            "선택: ${fmtAmPm(startHour, startMinute)} ~ ${fmtAmPm(endHour, endMinute)}",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

                        Spacer(Modifier.height(12.dp))
                        // 휴게시간
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("휴게시간", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showBreakSheet = true }) { Text("설정") }
                        }
                        Text("선택: ${breakMinutes}분", color = MaterialTheme.colorScheme.onSurfaceVariant)

                        Spacer(Modifier.height(12.dp))
                        // 근무 날짜
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("근무 날짜", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showDateDialog = true }) { Text("달력 열기") }
                        }
                        val preview = if (selectedDates.isEmpty()) "선택 없음" else "${selectedDates.size}일 근무"
                        Text("선택: $preview", color = MaterialTheme.colorScheme.onSurfaceVariant)

                        Spacer(Modifier.height(12.dp))
                        // 급여 날짜(매달)
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
                Row(Modifier.fillMaxWidth().padding(bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onBack) { Text("뒤로") }
                    Spacer(Modifier.weight(1f))
                    Button(onClick = { validateAndSubmit() }) { Text("저장") }
                }
            }
        }
    }

    /* ------------------- 시트/다이얼로그 ------------------- */
    if (showTaxSheet) {
        TaxSheet(
            currentEnabled = taxEnabled,
            current = taxConfig,
            onDismissApply = { result ->
                if (result == TaxConfig.NONE) { taxEnabled = false; taxConfig = TaxConfig.NONE }
                else { taxEnabled = true; taxConfig = result }
                showTaxSheet = false
            }
        )
    }
    if (showInsSheet) {
        InsuranceSheet(
            currentEnabled = insEnabled,
            current = insuranceConfig,
            onDismissApply = { result ->
                if (result == InsuranceConfig.NONE) { insEnabled = false; insuranceConfig = InsuranceConfig.NONE }
                else { insEnabled = true; insuranceConfig = result }
                showInsSheet = false
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
        DateMultiDialog(
            ym = ym,
            selected = selectedDates,            // Set<LocalDate>
            onYmChange = { ym = it },
            onDismiss = { showDateDialog = false },
            onDone = { set -> selectedDates = set; showDateDialog = false } // Set<LocalDate>
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

/* ----------------------------- 세금/보험 시트 ----------------------------- */
@Composable
private fun TaxSheet(
    currentEnabled: Boolean,
    current: TaxConfig,
    onDismissApply: (TaxConfig) -> Unit
) {
    var temp by remember { mutableStateOf(current) }
    var custom by remember {
        mutableStateOf(if (current is TaxConfig.CUSTOM_PERCENT) current.percent.toString() else "")
    }

    ModalBottomSheet(onDismissRequest = { onDismissApply(temp) }) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { onDismissApply(temp) }) { Text("‹ 뒤로") }
            Spacer(Modifier.weight(1f)); Text("세금 설정", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.weight(1f))
            TextButton(onClick = { onDismissApply(temp) }) { Text("완료") }
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SelectableRow("일용직 6.6%", temp == TaxConfig.DAY_6_6) {
                temp = if (temp == TaxConfig.DAY_6_6) TaxConfig.NONE else TaxConfig.DAY_6_6
            }
            SelectableRow("사업소득 3.3%", temp == TaxConfig.BIZ_3_3) {
                temp = if (temp == TaxConfig.BIZ_3_3) TaxConfig.NONE else TaxConfig.BIZ_3_3
            }
            SelectableRow("근로소득 간이세액표", temp == TaxConfig.WAGE_TABLE) {
                temp = if (temp == TaxConfig.WAGE_TABLE) TaxConfig.NONE else TaxConfig.WAGE_TABLE
            }
            HorizontalDivider()
            SelectableRow("직접 입력(%)", temp is TaxConfig.CUSTOM_PERCENT) {
                temp = if (temp is TaxConfig.CUSTOM_PERCENT) TaxConfig.NONE
                else TaxConfig.CUSTOM_PERCENT(custom.toDoubleOrNull() ?: 0.0)
            }
            OutlinedTextField(
                value = custom,
                onValueChange = {
                    val f = it.filter { ch -> ch.isDigit() || ch == '.' }.take(6)
                    custom = f
                    if (temp is TaxConfig.CUSTOM_PERCENT) {
                        temp = TaxConfig.CUSTOM_PERCENT(f.toDoubleOrNull() ?: 0.0)
                    }
                },
                placeholder = { Text("예: 5.0") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun InsuranceSheet(
    currentEnabled: Boolean,
    current: InsuranceConfig,
    onDismissApply: (InsuranceConfig) -> Unit
) {
    var temp by remember { mutableStateOf(current) }

    ModalBottomSheet(onDismissRequest = { onDismissApply(temp) }) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { onDismissApply(temp) }) { Text("‹ 뒤로") }
            Spacer(Modifier.weight(1f)); Text("보험 설정", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.weight(1f))
            TextButton(onClick = { onDismissApply(temp) }) { Text("완료") }
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SelectableRow("4대보험", temp == InsuranceConfig.FOUR) {
                temp = if (temp == InsuranceConfig.FOUR) InsuranceConfig.NONE else InsuranceConfig.FOUR
            }
            SelectableRow("고용보험만", temp == InsuranceConfig.EMPLOYMENT_ONLY) {
                temp = if (temp == InsuranceConfig.EMPLOYMENT_ONLY) InsuranceConfig.NONE else InsuranceConfig.EMPLOYMENT_ONLY
            }
            Spacer(Modifier.height(8.dp))
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

/* ----------------------------- 급여일 선택(휠) ----------------------------- */
@Composable
private fun PayDaySheet(
    initialDay: Int,
    onDismiss: () -> Unit,
    onDone: (Int) -> Unit
) {
    var day by remember { mutableStateOf(initialDay.coerceIn(1, 31)) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDismiss) { Text("‹ 뒤로") }
            Spacer(Modifier.weight(1f)); Text("급여 지급 날짜(매달)", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.weight(1f))
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
