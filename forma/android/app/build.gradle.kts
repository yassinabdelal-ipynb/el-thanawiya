import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ahmed.forma"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ahmed.forma"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val uploadProperties = Properties()
    val uploadFile = rootProject.file("key.properties")
    if (uploadFile.exists()) {
        uploadFile.inputStream().use { uploadProperties.load(it) }
        signingConfigs.create("upload") {
            keyAlias = uploadProperties.getProperty("keyAlias")
            keyPassword = uploadProperties.getProperty("keyPassword")
            storeFile = file(uploadProperties.getProperty("storeFile"))
            storePassword = uploadProperties.getProperty("storePassword")
        }
    }
    buildTypes {
        release {
            signingConfig = when {
                uploadFile.exists() -> signingConfigs.getByName("upload")
                System.getenv("FORMA_LOCAL_SIGNING") == "true" -> signingConfigs.getByName("debug")
                else -> null
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
