import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Version declared once in settings.gradle.kts (apply false) — actually applied here,
    // which is what processes google-services.json into the Android resources Firebase
    // needs at runtime. It was previously declared with `apply false` in this file too,
    // which registered the plugin but never ran it.
    id("com.google.gms.google-services")
}

// Standard Flutter release-signing pattern (https://flutter.dev/to/reference-keystore).
// key.properties is gitignored (see android/.gitignore) — it and the keystore file it
// points at must never be committed. Generate a real keystore once (`keytool -genkey
// -v -keystore <path> -keyalg RSA -keysize 2048 -validity 10000 -alias <alias>`) and
// create android/key.properties with:
//   storePassword=<...>
//   keyPassword=<...>
//   keyAlias=<...>
//   storeFile=<absolute or project-relative path to the .jks/.keystore>
// Store the keystore and its passwords in your CI secrets manager, not in this repo.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    // Loud, not silent: a release build with no real keystore falls back to the
    // publicly-known Flutter debug key, which lets anyone re-sign a modified APK as if
    // it came from this app's original signer. That's a fine, expected fallback for
    // `flutter run --release` during local development — it must never be the case for
    // a build actually intended for distribution.
    logger.warn(
        "\n\n" +
            "!!! WARNING: android/key.properties not found — release builds will be signed with the DEBUG keystore. !!!\n" +
            "!!! This is fine for local `flutter run --release`, but an app-store-bound `flutter build appbundle`/`apk` !!!\n" +
            "!!! must NOT ship this way. See the comment above this warning in app/build.gradle.kts.                  !!!\n\n"
    )
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.18.0"))
    // TODO: Add the dependencies for Firebase products you want to use
    // When using the BoM, don't specify versions in Firebase dependencies
    implementation("com.google.firebase:firebase-analytics")
    // Add the dependencies for any other desired Firebase products
    // https://firebase.google.com/docs/android/setup#available-libraries
    // Firebase Cloud Messaging (FCM)
    implementation("com.google.firebase:firebase-messaging")
}

android {
    namespace = "com.nivasaos.nivasaos_tenant_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nivasaos.nivasaos_tenant_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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
