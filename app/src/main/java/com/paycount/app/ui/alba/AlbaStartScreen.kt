@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui.alba

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.paycount.app.common.BreakSheet
import com.paycount.app.common.DateMultiDialog
import com.paycount.app.common.TimeSheet
import kotlinx.coroutines.launch                 // ✅ 추가
import java.time.LocalDate
import java.time.YearMonth
import java.util.Calendar
import kotlin.math.max

/* -------------------------------------------------------------------------- */
/*  메인(스타트) 스크린                                                         */
/* -------------------------------------------------------------------------- */
@Composable
fun AlbaStartScreen(
    onBack: () -> Unit,
    onGoToAlbaForm: () -> Unit,
    onEditAlba: (String) -> Unit,               // 수정 버튼
    albas: List<UICalendarAlba>,
    schedules: List<UICalendarSchedule>,
    onAddWork: (
        albaId: String,
        year: Int, month: Int, day: Int,
        startH: Int, startM: Int, endH: Int, endM: Int,
        breakMin: Int
    ) -> Unit,
) {
    val ctx = LocalContext.current
    var sheetTarget by remember { mutableStateOf<UICalendarAlba?>(null) }
    val expanded = remember { mutableStateMapOf<String, Boolean>() }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("알바 메인") },
                navigationIcon = { TextButton(onClick = onBack) { Text("‹  뒤로") } }
            )
        }
    ) { inner ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            /* 직접 등록 버튼 */
            item {
                ElevatedCard {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("직접 등록", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.weight(1f))
                        Button(onClick = onGoToAlbaForm) { Text("알바 등록하러 가기") }
                    }
                }
            }

            /* 등록한 알바 목록 */
            item { Text("등록한 알바", style = MaterialTheme.typography.titleLarge) }

            items(albas) { alba ->
                val todayPay = calcPayUntilToday(alba, schedules)
                val isExpanded = expanded[alba.id] == true

                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // 헤더
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier
                                    .size(10.dp)
                                    .background(parseColor(alba.colorHex))
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(alba.name, style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.width(8.dp))
                            Text("시급: %,d원".format(alba.hourlyWage), color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.weight(1f))
                        }

                        Text("오늘까지 급여: %,d원".format(todayPay))

                        // 액션 버튼
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { onEditAlba(alba.id) }) { Text("수정") }
                            Button(onClick = { sheetTarget = alba }) { Text("근무 추가") }
                            TextButton(onClick = { expanded[alba.id] = !isExpanded }) {
                                Text(if (isExpanded) "닫기" else "펼치기")
                            }
                        }

                        // 펼침 영역
                        if (isExpanded) {
                            val last = schedules
                                .filter { it.albaId == alba.id }
                                .maxByOrNull { it.year * 10000 + it.month * 100 + it.day }

                            Divider()
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text("급여일: 매월 ${alba.payDay}일", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                if (last != null) {
                                    Text(
                                        "최근 근무: %02d:%02d ~ %02d:%02d (휴게 %d분)".format(
                                            last.startHour, last.startMinute, last.endHour, last.endMinute, last.breakMinutes
                                        ),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                } else {
                                    Text("최근 근무 없음", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Text("세금/보험/가산정책은 카드의 ‘수정’에서 확인·변경하세요.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }

    // 근무 추가 바텀시트
    sheetTarget?.let { target ->
        AddWorkSheet(
            alba = target,
            onConfirm = { triples, sh, sm, eh, em, br ->
                triples.forEach { (y, m, d) ->
                    onAddWork(target.id, y, m, d, sh, sm, eh, em, br)
                }
            },
            onDismiss = { sheetTarget = null }
        )
    }
}

/* -------------------------------------------------------------------------- */
/*  근무 추가 바텀시트                                                          */
/* -------------------------------------------------------------------------- */
@Composable
private fun AddWorkSheet(
    alba: UICalendarAlba,
    onConfirm: (Set<Triple<Int, Int, Int>>, Int, Int, Int, Int, Int) -> Unit,
    onDismiss: () -> Unit
) {
    val ctx = LocalContext.current                       // ✅ 컨텍스트는 여기서 미리 받기
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // 시간/휴게/날짜 상태
    var startH by remember { mutableStateOf(9) }
    var startM by remember { mutableStateOf(0) }
    var endH by remember { mutableStateOf(18) }
    var endM by remember { mutableStateOf(0) }
    var breakMin by remember { mutableStateOf(0) }
    var showTime by remember { mutableStateOf(false) }
    var showBreak by remember { mutableStateOf(false) }
    var showDate by remember { mutableStateOf(false) }
    var dates by remember { mutableStateOf(setOf<LocalDate>()) } // LocalDate로 관리

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("근무 추가", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            IconButton(
                onClick = {
                    scope.launch { sheetState.hide() }              // ✅ launch 사용
                        .invokeOnCompletion { onDismiss() }
                }
            ) {
                Icon(imageVector = Icons.Filled.Close, contentDescription = "닫기")
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Surface(
                color = MaterialTheme.colorScheme.surfaceVariant,
                shape = MaterialTheme.shapes.medium
            ) {
                Column(Modifier.fillMaxWidth().padding(12.dp)) {
                    Text(
                        "등록 정보",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text("매장: ${alba.name}")
                    Text("시급: %,d원".format(alba.hourlyWage))
                }
            }

            // 버튼 3개: 날짜 / 시간 / 휴게
            FilledTonalButton(onClick = { showDate = true }, modifier = Modifier.fillMaxWidth()) {
                Text(if (dates.isEmpty()) "근무 날짜 선택" else "근무 날짜: ${dates.size}일")
            }
            FilledTonalButton(onClick = { showTime = true }, modifier = Modifier.fillMaxWidth()) {
                Text("근무 시간 설정  (%02d:%02d ~ %02d:%02d)".format(startH, startM, endH, endM))
            }
            FilledTonalButton(onClick = { showBreak = true }, modifier = Modifier.fillMaxWidth()) {
                Text("휴게시간 설정  (${breakMin}분)")
            }

            Button(
                onClick = {
                    if (dates.isEmpty()) {
                        Toast.makeText(ctx, "근무 날짜를 선택하세요.", Toast.LENGTH_SHORT).show() // ✅ LocalContext.current 사용 금지, 위 ctx 사용
                        return@Button
                    }
                    val triples: Set<Triple<Int, Int, Int>> =
                        dates.map { Triple(it.year, it.monthValue, it.dayOfMonth) }.toSet()

                    onConfirm(triples, startH, startM, endH, endM, breakMin)

                    scope.launch { sheetState.hide() }              // ✅ launch 사용
                        .invokeOnCompletion { onDismiss() }
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text("적용하기") }
        }
    }

    /* ----- 팝업들 ----- */
    if (showTime) {
        TimeSheet(
            startH = startH, startM = startM, endH = endH, endM = endM,
            onDismiss = { showTime = false },
            onDone = { sh, sm, eh, em ->
                startH = sh; startM = sm; endH = eh; endM = em
                showTime = false
            }
        )
    }
    if (showBreak) {
        BreakSheet(
            initial = breakMin,
            onDismiss = { showBreak = false },
            onDone = { br -> breakMin = br; showBreak = false }
        )
    }
    if (showDate) {
        val cal = Calendar.getInstance()
        val startYm = YearMonth.of(cal[Calendar.YEAR], cal[Calendar.MONTH] + 1)
        DateMultiDialog(
            ym = startYm,
            selected = dates,
            onYmChange = { /* 내부에서 관리 */ },
            onDismiss = { showDate = false },
            onDone = { sel -> dates = sel; showDate = false }
        )
    }
}

/* -------------------------------------------------------------------------- */
/*  유틸                                                                       */
/* -------------------------------------------------------------------------- */

private fun parseColor(hex: String): Color = try {
    Color(android.graphics.Color.parseColor(hex))
} catch (_: Throwable) {
    Color(0xFF3B82F6)
}

private fun calcPayUntilToday(alba: UICalendarAlba, schedules: List<UICalendarSchedule>): Long {
    val cal = Calendar.getInstance()
    val y = cal[Calendar.YEAR]
    val m = cal[Calendar.MONTH] + 1
    val today = cal[Calendar.DAY_OF_MONTH]
    var sum = 0L
    schedules.forEach { s ->
        if (s.albaId == alba.id && s.year == y && s.month == m && s.day <= today) {
            val mins = paidMinutes(s)
            sum += (mins / 60.0 * alba.hourlyWage).toLong()
        }
    }
    return sum
}

private fun paidMinutes(s: UICalendarSchedule): Int {
    val start = s.startHour * 60 + s.startMinute
    val end = s.endHour * 60 + s.endMinute
    val total = max(0, end - start)
    return max(0, total - s.breakMinutes)
}
