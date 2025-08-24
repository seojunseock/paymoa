// build.gradle.kts (프로젝트 루트)
plugins {
    // Android Gradle Plugin
    id("com.android.application") version "8.6.0" apply false

    // Kotlin
    id("org.jetbrains.kotlin.android") version "2.0.0" apply false

    // ✅ Kotlin 2.0용 Compose Gradle 플러그인 (루트에서 버전 선언 필수)
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.0" apply false

    // Firebase Google Services 플러그인
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// ⚠️ 여기에서 repositories 블록을 추가하지 않습니다.
// 저장소는 settings.gradle.kts 의 dependencyResolutionManagement 에서 관리합니다.
