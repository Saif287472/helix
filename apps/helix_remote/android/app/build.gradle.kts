plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
