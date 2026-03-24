// android/app/build.gradle.kts
import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ✅ 릴리즈 키스토어 읽기
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    }
}

android {
    namespace = "com.paycount.app"
    compileSdk = flutter.compileSdkVersion

    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.paycount.app"
        minSdk = 23
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }

        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
}

/**
 * Flutter가 기대하는 출력 경로
 * <프로젝트루트>/build/app/outputs/flutter-apk/
 */
val projectRoot: File = project.rootDir.parentFile
val flutterApkOutDir = File(projectRoot, "build/app/outputs/flutter-apk")

/**
 * ✅ debug APK 복사
 * 실제 생성: android/app/build/outputs/apk/debug/app-debug.apk
 * 목표 경로: build/app/outputs/flutter-apk/app-debug.apk
 */
val copyDebugApkToFlutterOut by tasks.registering(Copy::class) {
    from(layout.buildDirectory.file("outputs/apk/debug/app-debug.apk"))
    into(flutterApkOutDir)

    doFirst {
        if (!flutterApkOutDir.exists()) flutterApkOutDir.mkdirs()

        val src = layout.buildDirectory.file("outputs/apk/debug/app-debug.apk").get().asFile
        if (!src.exists()) {
            logger.lifecycle("copyDebugApkToFlutterOut: source APK not found, skipping.")
            this.enabled = false
        } else {
            logger.lifecycle("copyDebugApkToFlutterOut: copying ${src.absolutePath} -> ${flutterApkOutDir.absolutePath}")
        }
    }

    rename { "app-debug.apk" }
}

/**
 * ✅ release APK 복사
 * 실제 생성: android/app/build/outputs/apk/release/app-release.apk
 * 목표 경로: build/app/outputs/flutter-apk/app-release.apk
 */
val copyReleaseApkToFlutterOut by tasks.registering(Copy::class) {
    from(layout.buildDirectory.file("outputs/apk/release/app-release.apk"))
    into(flutterApkOutDir)

    doFirst {
        if (!flutterApkOutDir.exists()) flutterApkOutDir.mkdirs()

        val normalSrc = layout.buildDirectory.file("outputs/apk/release/app-release.apk").get().asFile
        val unsignedSrc = layout.buildDirectory.file("outputs/apk/release/app-release-unsigned.apk").get().asFile

        when {
            normalSrc.exists() -> {
                logger.lifecycle("copyReleaseApkToFlutterOut: copying ${normalSrc.absolutePath} -> ${flutterApkOutDir.absolutePath}")
                from(normalSrc)
            }
            unsignedSrc.exists() -> {
                logger.lifecycle("copyReleaseApkToFlutterOut: copying ${unsignedSrc.absolutePath} -> ${flutterApkOutDir.absolutePath}")
                from(unsignedSrc)
            }
            else -> {
                logger.lifecycle("copyReleaseApkToFlutterOut: source APK not found, skipping.")
                this.enabled = false
            }
        }
    }

    rename { "app-release.apk" }
}

/**
 * ✅ debug assemble/package 후 복사
 */
tasks.named("assemble") {
    finalizedBy(copyDebugApkToFlutterOut)
}
tasks.matching { it.name == "assembleDebug" || it.name == "packageDebug" }.all {
    finalizedBy(copyDebugApkToFlutterOut)
}

/**
 * ✅ release assemble/package 후 복사
 */
tasks.matching { it.name == "assembleRelease" || it.name == "packageRelease" }.all {
    finalizedBy(copyReleaseApkToFlutterOut)
}

/**
 * ✅ AAB 복사
 * 실제 생성: android/app/build/outputs/bundle/release/app-release.aab
 * 목표 경로: build/app/outputs/bundle/release/app-release.aab
 */
val flutterBundleOutDir = File(projectRoot, "build/app/outputs/bundle/release")

afterEvaluate {
    tasks.findByName("bundleRelease")?.doLast {
        val src = layout.buildDirectory.file("outputs/bundle/release/app-release.aab").get().asFile
        if (src.exists()) {
            if (!flutterBundleOutDir.exists()) flutterBundleOutDir.mkdirs()
            val dest = File(flutterBundleOutDir, "app-release.aab")
            src.copyTo(dest, overwrite = true)
            logger.lifecycle("✅ AAB copied: ${src.absolutePath} -> ${dest.absolutePath}")
        } else {
            logger.lifecycle("⚠️ AAB not found at: ${src.absolutePath}")
        }
    }
}