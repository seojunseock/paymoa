// android/build.gradle.kts
// ✅ 루트 빌드 스크립트 (Kotlin DSL)
// 주의: pluginManagement, include(":app")는 settings.gradle.kts로 옮겼습니다.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// gradle clean 지원
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
