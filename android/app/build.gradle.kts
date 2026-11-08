plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.privateagent.private_agent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time APIs on older devices).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.privateagent.private_agent"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 26: foreground-service types, gesture APIs and notification channels
        // all behave consistently from Android 8.0 upwards.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release key comes from CI secrets (PKCS12, alias "friday"). Without them
    // (local or fork builds) the release falls back to the debug key.
    val releaseStore = System.getenv("FRIDAY_KEYSTORE_PATH")
    val releasePassword = System.getenv("FRIDAY_KEYSTORE_PASSWORD")
    val hasReleaseKey = !releaseStore.isNullOrEmpty() && !releasePassword.isNullOrEmpty()

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseStore!!)
                storeType = "pkcs12"
                storePassword = releasePassword
                keyAlias = "friday"
                keyPassword = releasePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
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
    // Required by flutter_local_notifications for java.time support below API 26+.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
