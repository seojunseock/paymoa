// android/build.gradle.kts
// ✅ 루트 빌드 스크립트 (Kotlin DSL)
// 주의: pluginManagement, include(":app")는 settings.gradle.kts로 옮겼습니다.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 모든 서브프로젝트(플러그인 포함)의 Java/Kotlin 버전을 17로 통일
// → "source value 8 is obsolete" 경고 제거
subprojects {
    afterEvaluate {
        // Java 컴파일 옵션
        if (plugins.hasPlugin("java") || plugins.hasPlugin("java-library") ||
            plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        // Kotlin 컴파일 옵션
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            kotlinOptions {
                jvmTarget = "17"
            }
        }
    }
}

// gradle clean 지원
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
