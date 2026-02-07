// android/app/build.gradle.kts
import java.io.File

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.paycount.app"
    compileSdk = flutter.compileSdkVersion

    // 필요 시 NDK 버전 고정
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.paycount.app"

        // ✅ firebase_auth 때문에 최소 23 필요 (기존 flutter.minSdkVersion=21이라 에러남)
        minSdk = 23

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 에뮬레이터(x86_64)만 사용 – 한 곳에서만 지정
        ndk {
            abiFilters.clear()
            abiFilters += listOf("x86_64")
        }

        multiDexEnabled = true
    }

    buildTypes {
        release {
            // 데모용: 디버그 키로 서명
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Java/Kotlin 옵션 + Desugaring
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }
}

flutter { source = "../.." }

dependencies {
    // Java 8+ API 디슈가링
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // 멀티덱스
    implementation("androidx.multidex:multidex:2.0.1")
}

/**
 * ✅ 후처리: 생성된 APK를 Flutter가 기대하는 경로로 복사
 *   실제 생성: android/app/build/outputs/apk/debug/app-debug.apk
 *   Flutter 기대: <프로젝트루트>/build/app/outputs/flutter-apk/app-debug.apk
 */
val projectRoot: File = project.rootDir.parentFile  // .../paycount
val flutterOutDir = File(projectRoot, "build/app/outputs/flutter-apk")

val copyDebugApkToFlutterOut by tasks.registering(Copy::class) {
    // 소스 APK(존재하지 않으면 skip 되지 않게 doFirst에서 검사)
    from(layout.buildDirectory.file("outputs/apk/debug/app-debug.apk"))
    into(flutterOutDir)
    doFirst {
        if (!flutterOutDir.exists()) flutterOutDir.mkdirs()
        // 소스가 없으면 “정상 빌드가 아니었음” → 조용히 skip (에러로 막지 않음)
        val src = layout.buildDirectory.file("outputs/apk/debug/app-debug.apk").get().asFile
        if (!src.exists()) {
            logger.lifecycle("copyDebugApkToFlutterOut: source APK not found, skipping.")
            this.enabled = false
        } else {
            logger.lifecycle("copyDebugApkToFlutterOut: copying ${src.absolutePath} -> ${flutterOutDir.absolutePath}")
        }
    }
    rename { "app-debug.apk" }
}

/**
 * ✅ 어떤 경로로 빌드되든 후처리가 실행되도록, 대표 태스크들에 finalize 연결
 *  - assemble (항상 존재)
 *  - assembleDebug / packageDebug (있으면 자동 연결)
 */
tasks.named("assemble") { finalizedBy(copyDebugApkToFlutterOut) }
tasks.matching { it.name == "assembleDebug" || it.name == "packageDebug" }.all {
    finalizedBy(copyDebugApkToFlutterOut)
}
