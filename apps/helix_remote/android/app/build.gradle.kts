plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    buildTypes {
        release {
            // Use product-scoped env vars (HELIX_REMOTE_*) so that Local and Remote
            // release builds can never accidentally share the same signing credentials.
            val keystoreFile = project.rootProject.file("helix_remote.keystore")
            val storePassword = System.getenv("HELIX_REMOTE_STORE_PASSWORD") ?: ""
            val keyAlias = System.getenv("HELIX_REMOTE_KEY_ALIAS") ?: ""
            val keyPassword = System.getenv("HELIX_REMOTE_KEY_PASSWORD") ?: ""
            if (!keystoreFile.exists() ||
                storePassword.isBlank() ||
                keyAlias.isBlank() ||
                keyPassword.isBlank()) {
                throw org.gradle.api.GradleException(
                    "Release build requires helix_remote.keystore and HELIX_REMOTE_STORE_PASSWORD, " +
                    "HELIX_REMOTE_KEY_ALIAS, HELIX_REMOTE_KEY_PASSWORD. Debug signing is forbidden for Helix Remote release."
                )
            }
            signingConfig = signingConfigs.create("release") {
                storeFile = keystoreFile
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
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
