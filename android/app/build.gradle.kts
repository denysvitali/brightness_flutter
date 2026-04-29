plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "it.denv.brightness_flutter"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "it.denv.brightness_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePath = System.getenv("KEYSTORE_PATH")
    val keystoreStorePassword =
        System.getenv("KEYSTORE_STORE_PASSWORD") ?: System.getenv("KEYSTORE_PASSWORD")
    val keystoreKeyPassword =
        System.getenv("KEYSTORE_KEY_PASSWORD") ?: System.getenv("KEY_PASSWORD")
    val keystoreKeyAlias =
        System.getenv("KEYSTORE_KEY_ALIAS") ?: System.getenv("KEY_ALIAS") ?: "upload"
    val hasReleaseKeystore =
        !keystorePath.isNullOrBlank() &&
            !keystoreStorePassword.isNullOrBlank() &&
            !keystoreKeyPassword.isNullOrBlank()

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file(keystorePath)
                storePassword = keystoreStorePassword
                keyPassword = keystoreKeyPassword
                keyAlias = keystoreKeyAlias
            }
        }
    }

    buildTypes {
        debug {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.findByName("release")
            }
        }
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.findByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
