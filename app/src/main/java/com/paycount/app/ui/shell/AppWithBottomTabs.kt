package com.paycount.app.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.paycount.app.AlbaPatch
import com.paycount.app.LocalAppRepo
import com.paycount.app.ui.alba.AlbaFormInitial
import com.paycount.app.ui.alba.AlbaFormScreen
import com.paycount.app.ui.alba.AlbaStartScreen
import com.paycount.app.ui.alba.CalendarScreen
import com.paycount.app.ui.alba.UICalendarSchedule

@Composable
fun AppWithBottomTabs(
    selectedTab: Int,
    onSelectTab: (Int) -> Unit,
    startScreen: @Composable () -> Unit,
    calendarScreen: @Composable () -> Unit,
    profileScreen: @Composable () -> Unit,
) {
    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { onSelectTab(0) },
                    icon = { Icon(imageVector = Icons.Filled.Home, contentDescription = "메인") },
                    label = { Text("메인") }
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { onSelectTab(1) },
                    icon = { Icon(imageVector = Icons.Filled.CalendarMonth, contentDescription = "달력") },
                    label = { Text("달력") }
                )
                NavigationBarItem(
                    selected = selectedTab == 2,
                    onClick = { onSelectTab(2) },
                    icon = { Icon(imageVector = Icons.Filled.Person, contentDescription = "내정보") },
                    label = { Text("내정보") }
                )
            }
        }
    ) { inner ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues = inner)
        ) {
            when (selectedTab) {
                0 -> startScreen()
                1 -> calendarScreen()
                else -> profileScreen()
            }
        }
    }
}

/* ---------------- 네비 상태 + 저장소 연결 ---------------- */

/** 탭 0(메인) 안에서만 사용하는 루트 화면들 */
private sealed interface MainRoot {
    data object Start : MainRoot
    data class Form(val albaId: String? = null) : MainRoot // albaId==null이면 신규
}

@Composable
fun AppWithBottomTabs() {
    val repo = LocalAppRepo.current
    val albas by repo.albas.collectAsState()
    val schedules by repo.schedules.collectAsState()

    var selectedTab by remember { mutableStateOf(0) }
    var mainRoot by remember { mutableStateOf<MainRoot>(MainRoot.Start) }

    AppWithBottomTabs(
        selectedTab = selectedTab,
        onSelectTab = { tab ->
            selectedTab = tab
            // 탭 이동 시 메인 루트는 유지(폼 작성 중 탭 바꿨다가 돌아와도 계속 이어서 작성 가능)
        },
        /* ---------------- 메인 탭(알바 스타트/폼) ---------------- */
        startScreen = {
            when (val screen = mainRoot) {
                MainRoot.Start -> AlbaStartScreen(
                    onBack = { /* no-op */ },
                    onGoToAlbaForm = { mainRoot = MainRoot.Form(null) },
                    onEditAlba = { id -> mainRoot = MainRoot.Form(id) },
                    albas = albas,
                    schedules = schedules,
                    onAddWork = { aid, y, m, d, sh, sm, eh, em, br ->
                        repo.addSchedule(
                            UICalendarSchedule(
                                albaId = aid,
                                year = y, month = m, day = d,
                                startHour = sh, startMinute = sm,
                                endHour = eh, endMinute = em,
                                breakMinutes = br
                            )
                        )
                    }
                )

                is MainRoot.Form -> {
                    val initial: AlbaFormInitial? = screen.albaId?.let { id ->
                        repo.getFormInitial(id)
                    }

                    AlbaFormScreen(
                        onBack = { mainRoot = MainRoot.Start },
                        onSubmit = { result ->
                            if (screen.albaId == null) {
                                repo.saveAlbaForm(result)          // 신규
                            } else {
                                repo.updateAlbaFromForm(screen.albaId, result) // 수정
                            }
                            mainRoot = MainRoot.Start
                            selectedTab = 0
                        },
                        existingSchedules = schedules,
                        initial = initial
                    )
                }
            }
        },
        /* ---------------- 달력 탭 ---------------- */
        calendarScreen = {
            CalendarScreen(
                onBack = { selectedTab = 0 },
                albas = albas,
                schedules = schedules,
                onDeleteSchedule = { repo.deleteSchedule(it) },
                onUpdateSchedule = { repo.updateSchedule(it) },
                onAddSchedule = { repo.addSchedule(it) },
                onApplyWageForward = { aid, y, m, d, startMin, newWage ->
                    repo.applyWageForward(aid, y, m, d, startMin, newWage)
                },
                getSurchargePolicy = { repo.getProfile(it).surcharge },
                saveSurchargePolicy = { aid, p ->
                    repo.updateAlba(aid, AlbaPatch(surcharge = p))
                },
                getTaxPolicy = { repo.getProfile(it).tax },
                getInsurancePolicy = { repo.getProfile(it).insurance },
                goToAlbaForm = { selectedTab = 0; mainRoot = MainRoot.Form(it) }
            )
        },
        /* ---------------- 내정보 탭 ---------------- */
        profileScreen = {
            Text(
                text = "내정보 화면 준비중",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(24.dp)
            )
        }
    )
}
