plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Firebase plugin
    id("com.google.gms.google-services")
    // Flutter plugin (siempre al final)
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.my_porki"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true  // 🔥 FIX para notificaciones
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.my_porki"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib")

    // 🔥 Firebase
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")

    // 🔔 Desugaring requerido por flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}

