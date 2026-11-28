package chat.fluffy.fluffychat

import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodChannel

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings

import java.io.File

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(getApplicationContext())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    // Prevent Flutter engine gets destroyed on back button close.
    override fun createFlutterFragment(): FlutterFragment =
        super.createFlutterFragment().apply {
            arguments?.putBoolean("destroy_engine_with_fragment", false)
        }

    companion object {
        private const val APP_SETTINGS_CHANNEL = "chat.fluffychatx/app_settings"
        private const val LOGS_CHANNEL = "chat.fluffychatx/logs"

        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
                .also {
                    registerAppSettingsChannel(context, it)
                    registerLogsChannel(context, it)
                }
            engine = eng
            return eng
        }

        /// 「导出操作日志」用的通道：把文本写到系统的 Download 目录。
        ///
        /// Android 10+ 用 MediaStore 插一条 Downloads 记录（不需要存储权限）；
        /// 更老的系统直接写公共目录（老系统上需要 WRITE_EXTERNAL_STORAGE，
        /// 失败就当导出失败）。
        private fun registerLogsChannel(
            context: Context,
            engine: FlutterEngine,
        ) {
            val appContext = context.applicationContext
            MethodChannel(engine.dartExecutor.binaryMessenger, LOGS_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "saveToDownloads" -> {
                            val name = call.argument<String>("name")
                            val content = call.argument<String>("content")
                            if (name.isNullOrBlank() || content == null) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            try {
                                val uri = saveToDownloads(appContext, name, content)
                                result.success(uri != null)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
        }

        private fun saveToDownloads(
            context: Context,
            name: String,
            content: String,
        ): Uri? {
            val bytes = content.toByteArray(Charsets.UTF_8)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: return null
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return uri
            }
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS,
            )
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, name)
            file.writeBytes(bytes)
            return Uri.fromFile(file)
        }

        /// 设置页「打开系统通知设置」按钮用的小通道。
        ///
        /// Android 没有公开的 Flutter 插件能直接跳到应用通知设置页，与其为了
        /// 一个按钮加依赖，不如在这里直接 startActivity。
        private fun registerAppSettingsChannel(
            context: Context,
            engine: FlutterEngine,
        ) {
            val appContext = context.applicationContext
            MethodChannel(engine.dartExecutor.binaryMessenger, APP_SETTINGS_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "openNotificationSettings" -> {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, appContext.packageName)
                            } else {
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", appContext.packageName, null),
                                )
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            try {
                                appContext.startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                        "canInstallPackages" -> {
                            // Android 8+ 每个 App 单独授权「安装未知应用」，
                            // 没开的时候调起安装器可能什么都不发生（不抛异常），
                            // 所以安装前必须先问 PackageManager。
                            val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                appContext.packageManager.canRequestPackageInstalls()
                            } else {
                                true
                            }
                            result.success(allowed)
                        }
                        "openInstallPermissionSettings" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.fromParts("package", appContext.packageName, null),
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            try {
                                appContext.startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
        }

        // Make push services run in the same engine.
        // https://codeberg.org/UnifiedPush/flutter-connector/src/branch/main/unifiedpush_android/android/src/main/kotlin/org/unifiedpush/flutter/connector/UnifiedPushService.kt#L17-L32
        fun provideRunningEngine(context: Context): FlutterEngine {
            var eng = engine
            if (eng == null) {
                eng = provideEngine(context)
                eng.getLocalizationPlugin().sendLocalesToFlutter(
                    context.getResources().getConfiguration())
                eng.getDartExecutor().executeDartEntrypoint(
                    DartEntrypoint.createDefault())
            }
            return eng
        }
    }
}
