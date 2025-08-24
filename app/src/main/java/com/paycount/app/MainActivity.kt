package com.paycount.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import com.paycount.app.ui.alba.*
import com.paycount.app.ui.shell.AppWithBottomTabs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            MaterialTheme {
                Surface {
                    // 앱 전역 상태
                    var albas by remember { mutableStateOf(listOf<UICalendarAlba>()) }
                    var schedules by remember { mutableStateOf(listOf<UICalendarSchedule>()) }

                    var showAlbaForm by remember { mutableStateOf(false) }
                    var selectedTab by remember { mutableStateOf(0) }

                    AppWithBottomTabs(
                        selectedTab = selectedTab,
                        onSelectTab = { selectedTab = it },

                        // 메인(스타트)
                        startScreen = {
                            AlbaStartScreen(
                                onBack = { /* no-op */ },
                                onGoToAlbaForm = { showAlbaForm = true },
                                albas = albas,
                                schedules = schedules,
                                onAddWork = { albaId, y, m, d, sh, sm, eh, em, br ->
                                    schedules = schedules + UICalendarSchedule(
                                        id = makeId(),
                                        albaId = albaId,
                                        year = y, month = m, day = d,
                                        startHour = sh, startMinute = sm,
                                        endHour = eh, endMinute = em,
                                        breakMinutes = br,
                                        overrideHourlyWage = null
                                    )
                                    selectedTab = 1 // 달력으로 이동
                                }
                            )
                        },

                        // 달력
                        calendarScreen = {
                            CalendarScreen(
                                onBack = { selectedTab = 0 },
                                albas = albas,
                                schedules = schedules,

                                // 스케줄 삭제
                                onDeleteSchedule = { scheduleId ->
                                    schedules = schedules.filterNot { it.id == scheduleId }
                                },

                                // 스케줄 갱신
                                onUpdateSchedule = { updated ->
                                    schedules = schedules.map { if (it.id == updated.id) updated else it }
                                },

                                // “해당 근무 이후 모두 적용”
                                onApplyWageForward = { albaId, ey, em, ed, effectiveStartMin, newWage ->
                                    // 1) 알바 기본 시급 업데이트
                                    albas = albas.map { if (it.id == albaId) it.copy(hourlyWage = newWage) else it }

                                    // 2) 기준 시점 이후의 스케줄에 override 반영
                                    schedules = schedules.map { s ->
                                        if (s.albaId == albaId &&
                                            isSameOrAfterDateTime(
                                                y = s.year, m = s.month, d = s.day,
                                                startMin = s.startHour * 60 + s.startMinute,
                                                y2 = ey, m2 = em, d2 = ed, startMin2 = effectiveStartMin
                                            )
                                        ) s.copy(overrideHourlyWage = newWage) else s
                                    }
                                },

                                // 여러 구간 추가: 새 스케줄 추가
                                onAddSchedule = { newItem ->
                                    schedules = schedules + newItem
                                }
                            )
                        },

                        // 내정보(임시)
                        profileScreen = { SimpleProfileScreen() }
                    )

                    // 알바 폼
                    if (showAlbaForm) {
                        AlbaFormScreen(
                            onBack = { showAlbaForm = false },
                            onSubmit = { res ->
                                val newAlba = UICalendarAlba(
                                    id = makeId(),
                                    name = res.storeName,
                                    hourlyWage = res.hourlyWage,
                                    colorHex = res.colorHex,
                                    payDay = res.payDay
                                )
                                albas = albas + newAlba

                                if (res.selectedDates.isNotEmpty()) {
                                    val newSchedules = res.selectedDates.map { d ->
                                        UICalendarSchedule(
                                            id = makeId(),
                                            albaId = newAlba.id,
                                            year = d.year, month = d.monthValue, day = d.dayOfMonth,
                                            startHour = res.startHour24, startMinute = res.startMinute,
                                            endHour = res.endHour24, endMinute = res.endMinute,
                                            breakMinutes = res.breakMinutes,
                                            overrideHourlyWage = null
                                        )
                                    }
                                    schedules = schedules + newSchedules
                                }

                                showAlbaForm = false
                                selectedTab = 1 // 저장 후 달력으로
                            }
                        )
                    }
                }
            }
        }
    }
}

/* ----- 임시 프로필 ----- */
@Composable
private fun SimpleProfileScreen() {
    androidx.compose.material3.Text("내 정보 (준비중)")
}

/* ----- 유틸 ----- */
private fun makeId() = System.nanoTime().toString()

private fun isSameOrAfterDateTime(
    y: Int, m: Int, d: Int, startMin: Int,
    y2: Int, m2: Int, d2: Int, startMin2: Int
): Boolean = when {
    y > y2 -> true
    y < y2 -> false
    m > m2 -> true
    m < m2 -> false
    d > d2 -> true
    d < d2 -> false
    else -> startMin >= startMin2
}
