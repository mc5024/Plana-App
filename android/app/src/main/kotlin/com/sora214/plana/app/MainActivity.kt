package com.sora214.plana.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val documentSaver = DocumentSaver(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 启动即建通道:否则装完到第一次生成之间,系统设置里的「通知类别」是空的,
        // 用户想预先开横幅/声音/振动都没得开。
        LiveProgressService.ensureChannels(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        LiveProgressService.start(
                            this,
                            call.argument("title"),
                            call.argument("text"),
                            call.argument<Int>("total") ?: 0,
                            call.argument("short"),
                        )
                        result.success(null)
                    }

                    "channels" -> {
                        LiveProgressService.setChannelNames(
                            this,
                            call.argument<String>("progress") ?: "",
                            call.argument<String>("progressDesc") ?: "",
                            call.argument<String>("done") ?: "",
                            call.argument<String>("doneDesc") ?: "",
                        )
                        result.success(null)
                    }

                    "update" -> {
                        LiveProgressService.update(
                            call.argument<Int>("cur") ?: 0,
                            call.argument<Int>("total") ?: 0,
                            call.argument<Boolean>("indeterminate") ?: false,
                            call.argument<String>("title") ?: "Plana",
                            call.argument<String>("text") ?: "",
                            call.argument<String>("short") ?: "",
                        )
                        result.success(null)
                    }

                    "finish" -> {
                        LiveProgressService.finish(
                            call.argument<String>("title") ?: "Plana",
                            call.argument<String>("text") ?: "",
                            call.argument<String>("short") ?: "",
                            call.argument<Boolean>("keep") ?: true,
                            call.argument<String>("next") ?: "",
                            call.argument<String>("nextShort") ?: "",
                        )
                        result.success(null)
                    }

                    "stop" -> {
                        LiveProgressService.stop()
                        result.success(null)
                    }

                    "capabilities" -> result.success(
                        mapOf(
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "canPromote" to LiveProgressService.canPromote(this),
                        ),
                    )

                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        // 检查更新:版本号从系统读(不信 Dart 侧手抄的常量)。
        // 下载与安装不归本应用管 —— 只把用户送去 GitHub Release 页。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(
                        mapOf(
                            "versionCode" to AppVersion.code(this),
                            "versionName" to AppVersion.name(this),
                        ),
                    )

                    else -> result.notImplemented()
                }
            }

        // 鸿蒙的安卓兼容容器(卓易通 / 出境易)检测,判法见 HarmonyCompat。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARMONY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isContainer" -> result.success(HarmonyCompat.isContainer)
                    else -> result.notImplemented()
                }
            }

        // 大文件经系统保存对话框存出去(打包 ZIP):只传路径,原生侧边读边写,见 DocumentSaver。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOCUMENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveAs" -> documentSaver.save(
                        call.argument<String>("path") ?: "",
                        call.argument<String>("name") ?: "",
                        call.argument<String>("mime") ?: "application/octet-stream",
                        result,
                    )

                    else -> result.notImplemented()
                }
            }

        // 名字胶囊配色:预览图底部中间的亮度,抽样解码在原生侧算,见 PreviewTone。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TONE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "measure" -> PreviewTone.measure(
                        call.argument<String>("path"),
                        call.argument<ByteArray>("bytes"),
                        call.argument<Double>("x0") ?: 0.15,
                        call.argument<Double>("x1") ?: 0.85,
                        result,
                    )

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 先交给插件(file_picker 等)照常分发,再看是不是 DocumentSaver 那一单
        super.onActivityResult(requestCode, resultCode, data)
        documentSaver.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val CHANNEL = "plana/live_progress"
        private const val UPDATE_CHANNEL = "plana/update"
        private const val HARMONY_CHANNEL = "plana/harmony_compat"
        private const val DOCUMENT_CHANNEL = "plana/document"
        private const val TONE_CHANNEL = "plana/preview_tone"
    }
}
