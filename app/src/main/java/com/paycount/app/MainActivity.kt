package com.paycount.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import com.paycount.app.ui.shell.AppWithBottomTabs

// 화면에서 LocalAppRepo.current 로 저장소 접근
val LocalAppRepo = staticCompositionLocalOf<AppRepository> {
    error("AppRepository is not provided")
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            // ✅ inMemory() 대신 createInMemoryRepository() 사용
            val repo = remember { createInMemoryRepository() }

            CompositionLocalProvider(LocalAppRepo provides repo) {
                MaterialTheme {
                    AppWithBottomTabs()
                }
            }
        }
    }
}
