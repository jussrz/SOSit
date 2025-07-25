plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ⚠️ Make sure this matches the package in your MainActivity.kt file
    namespace = "com.example.sosit_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // Optional: replace or remove if managed by Flutter

    compileOptions {
        // These define the Java language version compatibility
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        // Kotlin compiler target version
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // ⚠️ This must also match your Kotlin package
        applicationId = "com.example.sosit_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for production release.
            // Currently using debug signing for test builds.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
