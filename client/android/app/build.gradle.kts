plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.syncm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.syncm"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["redirectSchemeName"] = "syncm"
        manifestPlaceholders["redirectHostName"] = "callback"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":spotify-app-remote"))

    // spotify-app-remote AAR подключён как голый файл, без транзитивных зависимостей.
    // Его типы размечены Jackson/JSR-305 аннотациями, которых нет в classpath, и ART
    // на каждой десериализации PlayerState сыпет "Unable to resolve ... annotation class".
    // Только для debug — release-сборке эти классы не нужны.
    debugImplementation("com.fasterxml.jackson.core:jackson-databind:2.17.2")
    debugImplementation("com.google.code.findbugs:jsr305:3.0.2")
}
