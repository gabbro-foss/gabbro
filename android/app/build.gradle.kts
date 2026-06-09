import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
keyProperties.load(keyPropertiesFile.inputStream())

android {
    namespace = "app.gabbro.gabbro"
    compileSdkVersion("android-36")
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.gabbro.gabbro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String
            keyPassword = keyProperties["keyPassword"] as String
            storeFile = file(keyProperties["storeFile"] as String)
            storePassword = keyProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    testOptions {
        unitTests {
            // Robolectric needs the merged Android resources/manifest on the
            // unit-test classpath to provide real framework class implementations.
            isIncludeAndroidResources = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.yubico.yubikit:android:3.1.0")
    implementation("com.yubico.yubikit:fido:3.1.0")
    implementation("androidx.biometric:biometric-ktx:1.2.0-alpha05")

    // JVM unit tests. Robolectric supplies real implementations of framework
    // classes (android.net.Uri, org.json, SharedPreferences) that are otherwise
    // stubbed to throw in plain unit tests — runs on the JVM, no device needed.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.13")
}
