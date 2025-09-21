// android/build.gradle.kts
// 루트 빌드 파일: Flutter가 settings.gradle(.kts)에서 플러그인/AGP 버전을 관리하므로
// 여기서는 저장소와 공통 태스크만 둡니다. (AGP 플러그인 선언 금지)

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
