// settings.gradle.kts (프로젝트 루트)

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    // ✅ Gradle이 필요한 JDK(예: 17)를 자동으로 찾고/다운로드하게 해주는 플러그인
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "paycount"
include(":app")
