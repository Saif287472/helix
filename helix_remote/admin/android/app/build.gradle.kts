plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The operator console never ships signed with the debug key (a well-known
// default that sits on every developer machine, so an APK signed with it could
// replace the real console on the operator's phone). Product-scoped names keep
// the console's signing material apart from the app's.
val releaseKeystoreFile = project.rootProject.file("helix_admin.keystore")
val releaseStorePassword = System.getenv("HELIX_ADMIN_STORE_PASSWORD") ?: ""
val releaseKeyAlias = System.getenv("HELIX_ADMIN_KEY_ALIAS") ?: ""
val releaseKeyPassword = System.getenv("HELIX_ADMIN_KEY_PASSWORD") ?: ""
val releaseSigningConfigured =
    releaseKeystoreFile.exists() &&
        releaseStorePassword.isNotBlank() &&
        releaseKeyAlias.isNotBlank() &&
        releaseKeyPassword.isNotBlank()
val missingReleaseSigningMessage =
    "Release build requires helix_admin.keystore and HELIX_ADMIN_STORE_PASSWORD, " +
        "HELIX_ADMIN_KEY_ALIAS, HELIX_ADMIN_KEY_PASSWORD. Debug signing is forbidden for the operator console release."

android {
    namespace = "com.helix.helix_admin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    dependencies {
        // The launch themes are AppCompat-based, which local_auth's unlock
        // prompt needs (the same as the user app).
        implementation("androidx.appcompat:appcompat:1.7.1")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.helix.helix_admin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
            // As the user app: no debug metadata or unused resources in the
            // artifact. Dart obfuscation is passed by the release gate.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
