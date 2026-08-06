// Firebase Cloud Messaging needs the Google Services plugin to turn
// google-services.json into build config. That file is deployment material
// and is deliberately not in the repository, and the plugin *fails the build*
// when it is absent rather than degrading - which would break every developer
// checkout and CI's Android debug build.
//
// So it is applied conditionally. With the file present, push is compiled in;
// without it, the app builds exactly as before and
// FirebasePushTokenSource.initialize() answers "unavailable" at runtime (see
// services/firebase_push_token_source.dart). One switch, both halves.
val googleServicesConfig = file("google-services.json")
val googleServicesConfigured = googleServicesConfig.exists()

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (googleServicesConfigured) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "google-services.json not found - building without Firebase push. " +
            "Incoming calls will not wake a closed app. Add the file to " +
            "android/app/ to enable it."
    )
}

val releaseKeystoreFile = project.rootProject.file("helix_remote.keystore")
val releaseStorePassword = System.getenv("HELIX_REMOTE_STORE_PASSWORD") ?: ""
val releaseKeyAlias = System.getenv("HELIX_REMOTE_KEY_ALIAS") ?: ""
val releaseKeyPassword = System.getenv("HELIX_REMOTE_KEY_PASSWORD") ?: ""
val releaseSigningConfigured =
    releaseKeystoreFile.exists() &&
        releaseStorePassword.isNotBlank() &&
        releaseKeyAlias.isNotBlank() &&
        releaseKeyPassword.isNotBlank()
val missingReleaseSigningMessage =
    "Release build requires helix_remote.keystore and HELIX_REMOTE_STORE_PASSWORD, " +
        "HELIX_REMOTE_KEY_ALIAS, HELIX_REMOTE_KEY_PASSWORD. Debug signing is forbidden for Helix Remote release."

android {
    namespace = "com.helix.remote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    }

    defaultConfig {
        applicationId = "com.helix.remote"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (releaseSigningConfigured) {
        signingConfigs {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Use product-scoped env vars (HELIX_REMOTE_*) so that Local and Remote
            // release builds can never accidentally share the same signing credentials.
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseTaskRequested = allTasks.any { task ->
        task.project == project && task.name.contains("Release")
    }
    if (releaseTaskRequested && !releaseSigningConfigured) {
        throw org.gradle.api.GradleException(missingReleaseSigningMessage)
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
