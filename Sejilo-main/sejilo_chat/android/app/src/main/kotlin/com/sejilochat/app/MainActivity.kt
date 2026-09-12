package com.sejilochat.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val messageChannelId = "sejilo_messages"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sejilo/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionStatus" -> result.success(permissionStatus())
                    "openAppSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    "requestEssential" -> {
                        if (permissionResult != null) {
                            result.error("request_in_progress", "A permission request is already open.", null)
                            return@setMethodCallHandler
                        }
                        val missing = essentialPermissions().filter {
                            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                        }
                        if (missing.isEmpty()) {
                            result.success(permissionStatus())
                        } else {
                            permissionResult = result
                            requestPermissions(missing.toTypedArray(), 4102)
                        }
                    }
                    "detectLocality" -> detectLocality(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sejilo/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "showIncoming") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val title = call.argument<String>("title") ?: "SejiloChat"
                val body = call.argument<String>("body") ?: "New nearby message"
                showIncomingNotification(title, body)
                result.success(true)
            }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                messageChannelId,
                "Nearby messages",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Messages received through the Sejilo Bluetooth mesh"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
    }

    private fun showIncomingNotification(title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, messageChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title.take(64))
            .setContentText(body.take(180))
            .setStyle(Notification.BigTextStyle().bigText(body.take(500)))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(pendingIntent)
            .build()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify((System.currentTimeMillis() and 0x7FFFFFFF).toInt(), notification)
    }

    private fun detectLocality(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("permission_denied", "Location permission is required.", null)
            return
        }
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER) -> LocationManager.PASSIVE_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> LocationManager.PASSIVE_PROVIDER
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager.getCurrentLocation(provider, null, mainExecutor) { location ->
                finishLocality(location, result)
            }
        } else {
            @Suppress("DEPRECATION")
            val location = manager.getLastKnownLocation(provider)
            finishLocality(location, result)
        }
    }

    private fun finishLocality(location: Location?, result: MethodChannel.Result) {
        if (location == null) {
            result.error("location_unavailable", "The device has no current location fix.", null)
            return
        }
        val locality = "Area ${"%.2f".format(Locale.US, location.latitude)}, ${"%.2f".format(Locale.US, location.longitude)}"
        runOnUiThread {
            result.success(
                mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy.toDouble(),
                    "name" to locality,
                ),
            )
        }
    }

    private fun essentialPermissions(): List<String> {
        val permissions = mutableListOf(
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.CAMERA,
                    Manifest.permission.RECORD_AUDIO,
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    permissions += Manifest.permission.BLUETOOTH_SCAN
                    permissions += Manifest.permission.BLUETOOTH_CONNECT
                    permissions += Manifest.permission.BLUETOOTH_ADVERTISE
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    permissions += Manifest.permission.POST_NOTIFICATIONS
                    permissions += Manifest.permission.READ_MEDIA_IMAGES
                } else {
                    permissions += Manifest.permission.READ_EXTERNAL_STORAGE
                }
        return permissions
    }

    private fun permissionStatus(): Map<String, Boolean> = mapOf(
        "bluetoothScan" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED),
        "bluetoothConnect" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED),
        "bluetoothAdvertise" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED),
        "location" to (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED),
        "camera" to (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED),
        "microphone" to (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED),
        "notifications" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED),
        "photos" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED else checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED),
    )

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4102) {
            permissionResult?.success(permissionStatus())
            permissionResult = null
        }
    }
}
