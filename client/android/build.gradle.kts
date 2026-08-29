// android/build.gradle.kts
//
// Версии Android Gradle Plugin и Kotlin объявлены ровно в одном месте —
// в settings.gradle.kts (AGP 8.11.1 / Kotlin 2.2.20 через plugins-блок settings).
// Легаси-блока `buildscript { classpath("com.android.tools.build:gradle:...") }`
// здесь быть не должно: он подмешивал в classpath корневого проекта вторую,
// более старую копию AGP (8.4.0) и Kotlin (1.9.22), которую наследовали все
// подпроекты Flutter-плагинов из Pub Cache.

allprojects {
    repositories {
        google()
        mavenCentral()
        flatDir {
            dirs("${rootProject.projectDir}/app/libs")
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}