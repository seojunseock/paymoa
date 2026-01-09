// android/settings.gradle.kts

pluginManagement {
    val flutterSdkPath = run {
        val props = java.util.Properties()
        file("local.properties").inputStream().use { props.load(it) }
        val path = props.getProperty("flutter.sdk")
        require(path != null) { "flutter.sdk not set in local.properties" }
        path
    }

    // Flutter Gradle 툴체인(includeBuild)
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// ✅ Flutter 스테이블과 검증된 호환 버전으로 고정
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.3.2" apply false   // ⬅︎ 8.7 → 8.3.2
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false // ⬅︎ 1.9.24 → 1.9.22
}

// 모듈 포함
include(":app")
