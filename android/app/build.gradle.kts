import com.android.build.api.dsl.ApplicationExtension
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取 local.properties
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

// 获取 keystore 路径
val keystorePath = localProperties.getProperty("flutter.keystore")
    ?: throw GradleException("flutter.keystore is not set in local.properties")

extensions.configure<ApplicationExtension> {
    namespace = "cn.ys1231.appproxy"
    compileSdk = 36  // Flutter 插件要求至少 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cn.ys1231.appproxy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28  // 跟随 tun2socks.aar api
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // 只保留最常用的架构（可选优化）
        // 移除 x86_64 可以减少包大小（大多数设备是 ARM）
        // ndk {
        //     abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        // }
    }

    signingConfigs {
        getByName("debug") {
            // Debug signing config
        }
        create("release") {
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
            storeFile = file(keystorePath)
            storePassword = System.getenv("KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // 启用代码压缩和混淆
            isMinifyEnabled = true
            isShrinkResources = true
            // 添加 ProGuard 规则文件
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        dex {
            useLegacyPackaging = true // 启用 Dex 压缩
        }
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            // 排除导致冲突的 META-INF 文件
            excludes += "META-INF/INDEX.LIST"
            excludes += "META-INF/io.netty.versions.properties"
            excludes += "META-INF/DEPENDENCIES"
            excludes += "META-INF/LICENSE"
            excludes += "META-INF/LICENSE.txt"
            // netty-codec-native-quic 的 5 个平台 jar 各带一份完全相同的 license 文本
            excludes += "META-INF/license/**"
            // 同上来源的元数据，Android 上无用途
            excludes += "META-INF/native-image/**"
            excludes += "META-INF/maven/**"
            excludes += "META-INF/versions/**/module-info.class"
            excludes += "META-INF/NOTICE"
            excludes += "META-INF/NOTICE.txt"
        }
    }
}

// AGP 9 Built-in Kotlin 顶层 DSL：替代已移除的 kotlin-android 插件
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("libs/tun2socks.aar"))
    // root shell：eBPF(sing-box) 模式用，tun2socks 路径不使用
    implementation("com.github.topjohnwu.libsu:core:6.0.0")
    implementation("com.google.code.gson:gson:2.13.2")
    implementation("io.ktor:ktor-server-cors:3.4.2")
    implementation("io.ktor:ktor-server-netty:3.4.2")
    implementation("io.ktor:ktor-server-auth:3.4.2")
    implementation("io.ktor:ktor-server-sse:3.4.2")
    implementation("io.modelcontextprotocol:kotlin-sdk-server:0.11.1")
    implementation("io.ktor:ktor-server-content-negotiation:3.4.2")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.4.2")
}
