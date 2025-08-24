package com.paycount.app.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

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
                .padding(paddingValues = inner) // 이름있는 파라미터로 모호성 제거
        ) {
            when (selectedTab) {
                0 -> startScreen()
                1 -> calendarScreen()
                else -> profileScreen()
            }
        }
    }
}
