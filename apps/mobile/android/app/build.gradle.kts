plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.fieldassist.field_assist"
    sourceSets.getByName("main").jniLibs.srcDir("../../../../packages/field_voice/native/moonshine/android")
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    // Reuse an installed matching NDK without changing the host Flutter SDK setting.
    System.getenv("FIELD_ASSIST_NDK_PATH")?.let { ndkPath = it }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.fieldassist.field_assist"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 31
        targetSdk = 36
        // Per-ABI APKs use the Flutter split configuration; AGP rejects both filters together.
        if (project.findProperty("split-per-abi") != "true") {
            ndk { abiFilters += listOf("arm64-v8a") }
        }
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Configure release credentials locally before distribution.
        }
    }

    packaging {
        jniLibs {
            // The upstream runtime archive includes this validation layer
            // even when only CPU inference modules are selected.
            excludes += "**/libVkLayer_khronos_validation.so"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Bundled Latin OCR model: available on first use without a network download.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
