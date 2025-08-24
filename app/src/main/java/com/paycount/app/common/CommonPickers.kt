@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.common

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/* -------------------- 시간 시트 -------------------- */
@Composable
fun TimeSheet(
    startH: Int,
    startM: Int,
    endH: Int,
    endM: Int,
    onDismiss: () -> Unit,
    onDone: (Int, Int, Int, Int) -> Unit
) {
    var sH by remember { mutableStateOf(startH) }
    var sM by remember { mutableStateOf(startM) }
    var eH by remember { mutableStateOf(endH) }
    var eM by remember { mutableStateOf(endM) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        SheetHeaderMini("근무시간", onBack = onDismiss) { onDone(sH, sM, eH, eM) }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("시작", style = MaterialTheme.typography.titleMedium)
            TimeWheels(hour24 = sH, minute = sM) { h, m -> sH = h; sM = m }
            HorizontalDivider()
            Text("종료", style = MaterialTheme.typography.titleMedium)
            TimeWheels(hour24 = eH, minute = eM) { h, m -> eH = h; eM = m }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun TimeWheels(
    hour24: Int,
    minute: Int,
    onChange: (Int, Int) -> Unit
) {
    var isPm by remember { mutableStateOf(hour24 >= 12) }
    var h12 by remember { mutableStateOf(((hour24 + 11) % 12) + 1) } // 1..12
    var m by remember { mutableStateOf((minute / 5) * 5) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        WheelCyclic(
            items = listOf("오전", "오후"),
            selectedIndex = if (isPm) 1 else 0,
            onSelected = { idx -> isPm = idx == 1; onChange(to24(h12, m, isPm), m) },
            widthDp = 84, visibleCount = 2, rowHeight = 40.dp
        )
        WheelCyclic(
            items = (1..12).map { it.toString().padStart(2, '0') },
            selectedIndex = h12 - 1,
            onSelected = { idx -> h12 = idx + 1; onChange(to24(h12, m, isPm), m) },
            widthDp = 72, visibleCount = 3, rowHeight = 40.dp
        )
        WheelCyclic(
            items = (0..55 step 5).map { it.toString().padStart(2, '0') },
            selectedIndex = m / 5,
            onSelected = { idx -> m = idx * 5; onChange(to24(h12, m, isPm), m) },
            widthDp = 72, visibleCount = 3, rowHeight = 40.dp
        )
    }
}

private fun to24(h12: Int, m: Int, pm: Boolean): Int = (h12 % 12) + if (pm) 12 else 0

/* -------------------- 루프 휠 (public) -------------------- */
@Composable
fun WheelCyclic(
    items: List<String>,
    selectedIndex: Int,
    onSelected: (Int) -> Unit,
    widthDp: Int,
    visibleCount: Int,
    rowHeight: Dp
) {
    val itemCount = items.size
    val loop = 2000
    val anchor = itemCount * (loop / 2)
    val density = LocalDensity.current
    val rowPx = with(density) { rowHeight.toPx() }
    val scope = rememberCoroutineScope()

    val selectRow = if (visibleCount % 2 == 1) visibleCount / 2 else (visibleCount / 2 - 1)

    val state: LazyListState = rememberLazyListState(
        initialFirstVisibleItemIndex = anchor + selectedIndex - selectRow,
        initialFirstVisibleItemScrollOffset = 0
    )
    val totalHeight = rowHeight * visibleCount

    Box(Modifier.width(widthDp.dp).height(totalHeight)) {
        LazyColumn(state = state, modifier = Modifier.fillMaxSize()) {
            items(itemCount * loop) { idx ->
                val realIdx = (idx % itemCount + itemCount) % itemCount
                val add = if (state.firstVisibleItemScrollOffset > rowPx / 2f) 1 else 0
                val center = state.firstVisibleItemIndex + selectRow + add
                val dist = abs(idx - center)
                val isSel = dist == 0
                val alpha = when (dist) { 0 -> 1f; 1 -> 0.55f; else -> 0.25f }
                Box(
                    Modifier.fillMaxWidth().height(rowHeight)
                        .clickable {
                            val target = idx - selectRow
                            scope.launch { state.animateScrollToItem(target, 0) }
                            onSelected(realIdx)
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        items[realIdx],
                        fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = alpha),
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
        LaunchedEffect(state.isScrollInProgress) {
            if (!state.isScrollInProgress) {
                val base = state.firstVisibleItemIndex
                val offset = state.firstVisibleItemScrollOffset
                val target = base + if (offset > rowPx / 2f) 1 else 0
                state.animateScrollToItem(target, 0)
                val realIdx = ((target + selectRow) % itemCount + itemCount) % itemCount
                onSelected(realIdx)
            }
        }
    }
}

/* -------------------- 휴게시간 시트 -------------------- */
@Composable
fun BreakSheet(
    initial: Int,
    onDismiss: () -> Unit,
    onDone: (Int) -> Unit
) {
    var custom by remember { mutableStateOf(initial.toString()) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        SheetHeaderMini("휴게시간", onBack = onDismiss) {
            onDone(custom.filter { it.isDigit() }.toIntOrNull() ?: 0)
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0, 30, 60).forEach { v ->
                    AssistChip(onClick = { custom = v.toString() }, label = { Text("${v}분") })
                    Spacer(Modifier.width(8.dp))
                }
            }
            OutlinedTextField(
                value = custom,
                onValueChange = { s -> custom = s.filter { it.isDigit() }.take(4) },
                label = { Text("직접 입력(분)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
        }
    }
}

/* -------------------- 날짜 다중 선택 (LocalDate) -------------------- */
@Composable
fun DateMultiDialog(
    ym: YearMonth,
    selected: Set<LocalDate>,
    onYmChange: (YearMonth) -> Unit,
    onDismiss: () -> Unit,
    onDone: (Set<LocalDate>) -> Unit
) {
    var curYm by remember { mutableStateOf(ym) }
    var sel by remember { mutableStateOf(selected.toSet()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = { onDone(sel) }) { Text("완료") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("‹ 뒤로") } },
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { curYm = curYm.minusMonths(1) }) { Text("◀") }
                Spacer(Modifier.width(8.dp))
                Text("${curYm.year}년 ${curYm.monthValue}월", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.width(8.dp))
                TextButton(onClick = { curYm = curYm.plusMonths(1) }) { Text("▶") }
            }
        },
        text = {
            Column {
                CalendarGridSmall(
                    ym = curYm,
                    selected = sel,
                    onToggle = { date ->
                        sel = sel.toMutableSet().apply { if (!add(date)) remove(date) }
                    }
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    text = if (sel.isEmpty()) "선택 없음" else "${sel.size}일 선택됨",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    )
}

@Composable
private fun CalendarGridSmall(
    ym: YearMonth,
    selected: Set<LocalDate>,
    onToggle: (LocalDate) -> Unit
) {
    val first = ym.atDay(1)
    val dim = ym.lengthOfMonth()
    val firstCol = (first.dayOfWeek.value % 7)
    Column {
        Row(Modifier.fillMaxWidth()) {
            listOf("일","월","화","수","목","금","토").forEach {
                Text(it, Modifier.weight(1f), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(6.dp))
        val totalCells = firstCol + dim
        val rows = (totalCells + 6) / 7
        repeat(rows) { r ->
            Row(Modifier.fillMaxWidth()) {
                repeat(7) { c ->
                    val idx = r * 7 + c
                    val day = idx - firstCol + 1
                    if (day in 1..dim) {
                        val date = ym.atDay(day)
                        val isSel = selected.contains(date)
                        val bg = if (isSel) Color(0xFF22C55E).copy(alpha = 0.25f) else Color.Transparent
                        Box(
                            Modifier.weight(1f).padding(2.dp)
                                .background(bg, shape = MaterialTheme.shapes.small)
                                .clickable { onToggle(date) }
                                .padding(vertical = 10.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(day.toString(), color = if (isSel) Color(0xFF16A34A) else MaterialTheme.colorScheme.onSurface)
                        }
                    } else {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/* -------------------- 공용 헤더 (public) -------------------- */
@Composable
fun SheetHeaderMini(title: String, onBack: () -> Unit, onDone: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TextButton(onClick = onBack) { Text("‹ 뒤로") }
        Spacer(Modifier.weight(1f))
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.weight(1f))
        TextButton(onClick = onDone) { Text("완료") }
    }
}
