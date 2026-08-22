plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing template (TASK-039). android/key.properties is gitignored;
// see android/key.properties.example and android/SIGNING.md. Absence is a
// deliberate fallback so `flutter build apk --release` still works on a
// clean checkout (debug keystore, not a Play upload).
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "za.co.basileia.keryx"
    // flutter_secure_storage requires Android API 37; minSdk remains 26.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "za.co.basileia.keryx"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keystorePropertiesFile.exists()) {
                    signingConfigs.getByName("release")
                } else {
                    logger.warn(
                        "android/key.properties is missing; signing the release APK with the debug keystore. See android/SIGNING.md.",
                    )
                    signingConfigs.getByName("debug")
                }
            // R8 is required so the keep rules in proguard-rules.pro actually
            // run. flutter_webrtc / livekit_client / mobile_scanner JNI and
            // ML Kit classes are stripped without them.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
