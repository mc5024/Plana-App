import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名配置(android/key.properties,已在 .gitignore 中排除)。
// 文件不存在时 release 回落 debug 签名,本地开发照常;正式出包必须存在,
// 否则换机/重装 SDK 后签名会变,老用户无法覆盖升级(只能卸载重装丢数据)。
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null
// 真机图库验收可单独安装；显式开关适用于 debug/profile/release，
// 便于用优化构建验收性能。未传开关时所有构建保持原包名。
val planaGalleryTest = providers.gradleProperty("planaGalleryTest").orNull == "true"

android {
    namespace = "com.sora214.plana.app"
    compileSdk = 36 // Notification.ProgressStyle(灵动岛/Live Updates)需 API 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (planaGalleryTest) "com.sora214.plana.app.gallerytest"
            else "com.sora214.plana.app"
        // 24 原是本地超分的 Vulkan compute 要求;那条线已下线,这里保持 24 不动 ——
        // 往下降是另一件事(得把所有插件重新验一遍),不该顺手改。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName + if (planaGalleryTest) "-gallery-test" else ""
        manifestPlaceholders["galleryTestLabel"] =
            if (planaGalleryTest) "Plana 图库测试" else "Plana App"
        ndk {
            // 只出 arm64(覆盖现代机型);出包文件名也带着这个 ABI。
            abiFilters += "arm64-v8a"
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                // AGP 默认只开 v2(minSdk 24 用不上 v1)。v3 额外带来密钥轮换能力:
                // 万一密钥泄露或需要更换,Android 9+ 能凭轮换链平滑过渡,
                // 而不是让全部老用户卸载重装。低版本自动回落 v2,无兼容风险。
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 就用正式签名;没有则回落 debug 签名,
            // 让 `flutter run --release` 在本机仍可用。**对外分发必须用正式签名**。
            // 并存测试包始终沿用其调试签名，以保留已安装测试版的数据。
            signingConfig = if (planaGalleryTest) {
                signingConfigs.getByName("debug")
            } else if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // ONNX Runtime 的 JNI 按类名字符串反查 Java 类,被 R8 改名后
            // 进程级 abort。规则见 proguard-rules.pro。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // 出包文件名带上版本号与 ABI,沿用 1.0.0 起就在用的那套写法
    // (Plana-1.0.2-arm64-v8a.apk)—— 默认的 app-release.apk 发几版下来
    // 下载目录里全是同名文件,只能靠日期猜哪个是哪个。
    //
    // ⚠ 这只改 Gradle 的产物名(build/app/outputs/apk/release/)。Flutter 之后
    //   还会把它复制一份成 build/app/outputs/flutter-apk/app-release.apk,
    //   那个名字是 flutter_tools 写死的,改不了 —— **对外分发拿 apk/release/ 那个**。
    applicationVariants.all {
        outputs.all {
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl)
                .outputFileName = "Plana-$versionName-arm64-v8a.apk"
        }
    }

    packaging {
        jniLibs {
            // defaultConfig.abiFilters 管不到插件 AAR 里预编译的 .so:
            // jni/jni_flutter 就把 libdartjni.so 的 v7a/x86_64 版本一起打进来了
            // (181KB 死重,本 app 只出 arm64)。见 audit-findings F0-08。
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    // 离线词库索引(assets/danbooru.tagidx,近 10MB)不压缩:引擎读压缩过的 asset
    // 会在 UI 线程上整份解压,不压缩则直接 mmap。见 lib/features/editor/data/local_tag_db.dart。
    androidResources {
        noCompress += "tagidx"
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

// 单独运行 Gradle 不会生成 Flutter 的原生插件注册文件。缺失时 APK
// 仍能编译，却会在 path_provider 的 JNI 调用处启动崩溃，必须在出包前拦截。
val verifyFlutterPluginRegistrant = tasks.register("verifyFlutterPluginRegistrant") {
    doLast {
        check(file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java").isFile) {
            "Missing Flutter plugin registrant. Run 'flutter pub get' in the project root before building."
        }
    }
}
tasks.named("preBuild") {
    dependsOn(verifyFlutterPluginRegistrant)
}

dependencies {
    // NotificationCompat.ProgressStyle + setRequestPromotedOngoing:
    // 跨版本请求把进度通知提升上岛(状态栏胶囊/锁屏);低版本自动 no-op。
    // 框架 Notification.Builder 在 android-36(stable)尚无 requestPromotedOngoing,故走 compat。
    implementation("androidx.core:core:1.18.0")
}
