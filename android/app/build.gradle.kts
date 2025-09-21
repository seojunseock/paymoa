// android/app/build.gradle.kts
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.paycount.app"

    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "com.paycount.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ 플러그인이 요구하는 NDK 27
    ndkVersion = "27.0.12077973"

    // ✅ Java 8+ API 사용을 위한 desugaring + JVM 17
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        // 🔹 Debug: shrink/minify 모두 꺼둠 (개발 속도/안정성)
        debug {
            isMinifyEnabled = false
            // 혹시 다른 곳에서 강제로 켜졌을 수 있어 명시적으로 꺼줍니다
            isShrinkResources = false
        }

        // 🔹 Release: 리소스 축소가 필요하면 minify와 함께 켭니다
        release {
            // 필요 없으면 둘 다 false로 두세요.
            // isMinifyEnabled = false
            // isShrinkResources = false

            // 👉 리소스 축소를 쓰고 싶다면 아래 두 줄을 함께 켜야 합니다.
            isMinifyEnabled = true          // R8 코드 축소
            isShrinkResources = true        // 리소스 축소(= minify가 켜져 있어야 허용)

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ desugaring 런타임(필수)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
