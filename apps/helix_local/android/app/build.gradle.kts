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
            if (keystoreFile.exists()) {
                signingConfig = signingConfigs.create("release") {
                    storeFile = keystoreFile
                    storePassword = System.getenv("HELIX_LOCAL_STORE_PASSWORD") ?: ""
                    keyAlias = System.getenv("HELIX_LOCAL_KEY_ALIAS") ?: ""
                    keyPassword = System.getenv("HELIX_LOCAL_KEY_PASSWORD") ?: ""
                }
            } else {
                val isCI = System.getenv("CI") != null || System.getenv("STRICT_MODE") != null
                if (isCI) {
                    throw org.gradle.api.GradleException(
                        "Release build requires helix_local.keystore and HELIX_LOCAL_* signing env vars. " +
                        "Do not use the shared release.keystore for Helix Local."
                    )
                }
                signingConfig = signingConfigs.getByName("debug")
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
