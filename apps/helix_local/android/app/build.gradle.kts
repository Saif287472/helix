plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.helix.local"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.helix.local"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Use product-scoped env vars (HELIX_LOCAL_*) so that Local and Remote
            // release builds can never accidentally share the same signing credentials.
            val keystoreFile = project.rootProject.file("helix_local.keystore")
            val storePassword = System.getenv("HELIX_LOCAL_STORE_PASSWORD") ?: ""
            val keyAlias = System.getenv("HELIX_LOCAL_KEY_ALIAS") ?: ""
            val keyPassword = System.getenv("HELIX_LOCAL_KEY_PASSWORD") ?: ""
            if (!keystoreFile.exists() ||
                storePassword.isBlank() ||
                keyAlias.isBlank() ||
                keyPassword.isBlank()) {
                throw org.gradle.api.GradleException(
                    "Release build requires helix_local.keystore and HELIX_LOCAL_STORE_PASSWORD, " +
                    "HELIX_LOCAL_KEY_ALIAS, HELIX_LOCAL_KEY_PASSWORD. Debug signing is forbidden for Helix Local release."
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
