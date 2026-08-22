import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.agronizer.greengrow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.agronizer.greengrow"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
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
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Local `flutter run --release` without a keystore.
                signingConfigs.getByName("debug")
            }
            ndk {
                // Play + Flutter 3.44 require stripped .so with symbols in BUNDLE-METADATA.
                debugSymbolLevel = "SYMBOL_TABLE"
                // AGP forbids ndk.abiFilters when ABI splits are enabled (`--split-per-abi`).
                // build_app.ps1 passes -P disable-abi-filtering=true on that APK path.
                if (project.findProperty("disable-abi-filtering") != "true") {
                    // Flutter's plugin fills defaultConfig with all ABIs; += would keep them.
                    abiFilters.clear()
                    abiFilters.add("arm64-v8a")
                }
            }
            packaging {
                jniLibs {
                    excludes += listOf(
                        "**/armeabi-v7a/**",
                        "**/armeabi/**",
                        "**/x86/**",
                        "**/x86_64/**",
                    )
                }
            }
            // R8 strips Gson generic signatures unless these rules are applied —
            // without them scheduled notifications crash with "Missing type parameter".
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
