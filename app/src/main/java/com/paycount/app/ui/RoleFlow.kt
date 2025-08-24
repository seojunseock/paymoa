@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.paycount.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * 역할 선택 → 사장님/알바생 메인 흐름의 공용 UI.
 * NavHost 없이도 콜백으로 화면 이동 연결 가능.
 *
 * MainActivity 예시:
 *   RoleSelectionScreen(
 *     onOwner = { /* nav to ownerHome */ },
 *     onAlba  = { /* nav to albaHome */ },
 *     onLogout = { /* signOut */ }
 *   )
 */

@Composable
fun RoleSelectionScreen(
    onOwner: () -> Unit,
    onAlba: () -> Unit,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier
) {
    Scaffold(
        topBar = { CenterAlignedTopAppBar(title = { Text("로그인 성공!") }) }
    ) { innerPadding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            BigButton(text = "사장님으로 시작하기", onClick = onOwner)
            BigButton(text = "알바생으로 시작하기", onClick = onAlba)
            BigButton(text = "로그아웃", onClick = onLogout)
        }
    }
}

@Composable
fun OwnerMainScreen(
    onBack: () -> Unit,
    onGoToStoreForm: () -> Unit,
    modifier: Modifier = Modifier
) {
    Scaffold(
        topBar = { CenterAlignedTopAppBar(title = { Text("사장님 메인") }) }
    ) { innerPadding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Title("사장님 대시보드 (임시)")
            BigButton(text = "매장 설정하러 가기", onClick = onGoToStoreForm)
            BigButton(text = "뒤로가기", onClick = onBack)
        }
    }
}

@Composable
fun AlbaMainScreen(
    onBack: () -> Unit,
    onGoToCode: () -> Unit,
    onGoToAlbaForm: () -> Unit,
    modifier: Modifier = Modifier
) {
    Scaffold(
        topBar = { CenterAlignedTopAppBar(title = { Text("알바생 메인") }) }
    ) { innerPadding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Title("알바생 대시보드 (임시)")
            BigButton(text = "코드 입력", onClick = onGoToCode)
            BigButton(text = "알바 등록하기", onClick = onGoToAlbaForm)
            BigButton(text = "뒤로가기", onClick = onBack)
        }
    }
}

/* ---------------------- 공용 UI 컴포넌트 ---------------------- */

@Composable
private fun BigButton(
    text: String,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        contentPadding = PaddingValues(vertical = 16.dp)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun Title(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
        modifier = Modifier.padding(bottom = 8.dp)
    )
}

/* ---------------------- 파일 단독 미리보기(선택) ---------------------- */
@Composable
fun RoleFlowMiniDemo() {
    val screen = remember { mutableStateOf("role") }
    when (screen.value) {
        "role" -> RoleSelectionScreen(
            onOwner = { screen.value = "owner" },
            onAlba = { screen.value = "alba" },
            onLogout = { screen.value = "role" }
        )
        "owner" -> OwnerMainScreen(
            onBack = { screen.value = "role" },
            onGoToStoreForm = { /* TODO */ }
        )
        "alba" -> AlbaMainScreen(
            onBack = { screen.value = "role" },
            onGoToCode = { /* TODO */ },
            onGoToAlbaForm = { /* TODO */ }
        )
    }
}
