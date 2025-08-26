@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.paycount.app.LocalAppRepo
import com.paycount.app.ui.alba.*
import kotlinx.coroutines.flow.collectLatest

/* -------- 파라미터 없는 래퍼: MainActivity에서 이것만 호출 -------- */
@Composable
fun AppWithBottomTabs() {
    var selected by remember { mutableStateOf(0) }
    AppWithBottomTabs(
        selectedTab = selected,
        onSelectTab = { selected = it },
        startScreen = { StartTab(onRequestGoCalendar = { selected = 1 }) },
        calendarScreen = { CalendarTab() },
        profileScreen = { ProfileTab() }
    )
}

@Composable
fun AppWithBottomTabs(
    selectedTab: Int,
    onSelectTab: (Int) -> Unit,
    startScreen: @Composable () -> Unit,
    calendarScreen: @Composable () -> Unit,
    profileScreen: @Composable () -> Unit
) {
    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { onSelectTab(0) },
                    icon = { Icon(Icons.Filled.Home, contentDescription = "메인") },
                    label = { Text("메인") }
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { onSelectTab(1) },
                    icon = { Icon(Icons.Filled.CalendarMonth, contentDescription = "달력") },
                    label = { Text("달력") }
                )
                NavigationBarItem(
                    selected = selectedTab == 2,
                    onClick = { onSelectTab(2) },
                    icon = { Icon(Icons.Filled.Person, contentDescription = "내정보") },
                    label = { Text("내정보") }
                )
            }
        }
    ) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            when (selectedTab) {
                0 -> startScreen()
                1 -> calendarScreen()
                else -> profileScreen()
            }
        }
    }
}

/* ----------------------------- Start 탭 ----------------------------- */

@Composable
private fun StartTab(onRequestGoCalendar: () -> Unit) {
    val repo = LocalAppRepo.current

    // 폼 열기 플래그
    var showForm by remember { mutableStateOf(false) }

    // 저장소 상태 구독
    val albas by repo.albas.collectAsState()
    val schedules by repo.schedules.collectAsState()

    if (showForm) {
        // 폼 화면 – 저장하면 저장소에 반영
        AlbaFormScreen(
            onBack = { showForm = false },
            onSubmit = { res ->
                repo.saveAlbaForm(res)   // 매장명 중복 체크/초기 스케줄 생성은 저장소에서 처리
                showForm = false
            }
        )
        return
    }

    // 네가 올린 스타트 화면 그대로 사용
    AlbaStartScreen(
        onBack = { /* 메인 탭은 뒤로 없음 */ },
        onGoToAlbaForm = { showForm = true },
        albas = albas,
        schedules = schedules,
        onAddWork = { albaId, y, m, d, sh, sm, eh, em, br ->
            repo.addSchedule(
                UICalendarSchedule(
                    albaId = albaId,
                    year = y, month = m, day = d,
                    startHour = sh, startMinute = sm,
                    endHour = eh, endMinute = em,
                    breakMinutes = br
                )
            )
            // 추가 후 바로 달력으로 이동하고 싶으면 아래 주석 해제
            // onRequestGoCalendar()
        }
    )
}

/* ----------------------------- Calendar 탭 ----------------------------- */

@Composable
private fun CalendarTab() {
    val repo = LocalAppRepo.current
    val albas by repo.albas.collectAsState()
    val schedules by repo.schedules.collectAsState()

    CalendarScreen(
        onBack = { /* no-op */ },

        albas = albas,
        schedules = schedules,

        onDeleteSchedule = { id -> repo.deleteSchedule(id) },
        onUpdateSchedule = { s -> repo.updateSchedule(s) },
        onAddSchedule = { s -> repo.addSchedule(s) },

        onApplyWageForward = { aid, y, m, d, startMin, w ->
            repo.applyWageForward(aid, y, m, d, startMin, w)
        },

        getSurchargePolicy = { aid -> repo.getProfile(aid).surcharge },
        saveSurchargePolicy = { aid, pol -> repo.updateAlba(aid, com.paycount.app.AlbaPatch(surcharge = pol)) },

        getTaxPolicy = { aid -> repo.getProfile(aid).tax },
        getInsurancePolicy = { aid -> repo.getProfile(aid).insurance },

        goToAlbaForm = { /* 필요한 경우 Start 탭에서 열기 */ }
    )
}

/* ----------------------------- Profile 탭 ----------------------------- */

@Composable
private fun ProfileTab() {
    Scaffold(topBar = { CenterAlignedTopAppBar(title = { Text("내정보") }) }) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            Text(
                "프로필 화면은 추후 연결 예정",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
