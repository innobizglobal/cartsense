plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("CARTSENSE_KEYSTORE_FILE")

android {
    namespace = "com.innobizglobal.cartsense_lite"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.innobizglobal.cartsense_lite"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        releaseKeystorePath?.let { keystorePath ->
            create("cartsenseRelease") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("CARTSENSE_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CARTSENSE_KEY_ALIAS")
                keyPassword = System.getenv("CARTSENSE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // CI supplies the stable CartSense beta key through encrypted
            // GitHub secrets. Local builds fall back to Android's debug key.
            signingConfig = signingConfigs.findByName("cartsenseRelease")
                ?: signingConfigs.getByName("debug")
            // ML Kit discovers several runtime components through manifest
            // metadata and reflection. Keep those components intact in this
            // private beta build until device coverage is established.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    implementation("com.google.mlkit:text-recognition:16.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
