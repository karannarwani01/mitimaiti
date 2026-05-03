plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.mitimaiti.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mitimaiti.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        vectorDrawables { useSupportLibrary = true }
    }

    buildTypes {
        debug {
            buildConfigField("String", "BASE_URL", "\"https://mitimaiti-backend-tyxa.onrender.com/v1/\"")
            buildConfigField("String", "SOCKET_URL", "\"https://mitimaiti-backend-tyxa.onrender.com\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "BASE_URL", "\"https://mitimaiti-backend-tyxa.onrender.com/v1/\"")
            buildConfigField("String", "SOCKET_URL", "\"https://mitimaiti-backend-tyxa.onrender.com\"")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
}

dependencies {
    // Compose BOM 2025.03.01 — latest stable (March 2025)
    val composeBom = platform("androidx.compose:compose-bom:2025.03.01")
    implementation(composeBom)

    // Core
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.activity:activity-compose:1.10.1")

    // Lifecycle
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.0")

    // Compose UI
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.animation:animation")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.9.0")

    // Image loading
    implementation("io.coil-kt:coil-compose:2.7.0")

    // Networking
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-gson:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.google.code.gson:gson:2.11.0")

    // WebSocket
    implementation("io.socket:socket.io-client:2.1.1")

    // DataStore
    implementation("androidx.datastore:datastore-preferences:1.1.4")

    // Location
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Debug
    debugImplementation("androidx.compose.ui:ui-tooling")
}
