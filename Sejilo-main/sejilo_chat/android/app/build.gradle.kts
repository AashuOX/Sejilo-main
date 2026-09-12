import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing config from key.properties file (local dev) or env vars (CI/CD)
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties()
if (keyPropsFile.exists()) {
    keyProps.load(keyPropsFile.inputStream())
}

val releaseKeyStorePath = System.getenv("SEJILO_ANDROID_KEYSTORE")
    ?: keyProps.getProperty("storeFile")?.let { rootProject.file(it).absolutePath }
val releaseKeyAlias = System.getenv("SEJILO_ANDROID_KEY_ALIAS")
    ?: keyProps.getProperty("keyAlias")
val releaseStorePassword = System.getenv("SEJILO_ANDROID_STORE_PASSWORD")
    ?: keyProps.getProperty("storePassword")
val releaseKeyPassword = System.getenv("SEJILO_ANDROID_KEY_PASSWORD")
    ?: keyProps.getProperty("keyPassword")
val hasReleaseSigning = listOf(
    releaseKeyStorePath,
    releaseKeyAlias,
    releaseStorePassword,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.sejilochat.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sejilochat.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeyStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

val verifyReleaseSigning by tasks.registering {
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Release signing is required. Set SEJILO_ANDROID_KEYSTORE, " +
                    "SEJILO_ANDROID_KEY_ALIAS, SEJILO_ANDROID_STORE_PASSWORD, " +
                    "and SEJILO_ANDROID_KEY_PASSWORD."
            )
        }
    }
}

tasks.configureEach {
    if (name == "validateSigningRelease") {
        dependsOn(verifyReleaseSigning)
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
