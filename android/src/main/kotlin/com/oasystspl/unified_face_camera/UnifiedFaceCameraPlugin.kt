package com.oasystspl.unified_face_camera

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class UnifiedFaceCameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingPermissionResult: Result? = null

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 991
        private const val LOCATION_PERMISSION_REQUEST_CODE = 992
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "unified_face_camera")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "addTimestamp" -> {
                val path = call.argument<String>("path")
                val latitude = call.argument<Double>("latitude")
                val longitude = call.argument<Double>("longitude")
                android.util.Log.d("UnifiedFaceCamera", "addTimestamp called for path: $path, lat: $latitude, lng: $longitude")
                if (path != null) {
                    val timestampedPath = ImageUtils.addTimestamp(path, latitude, longitude)
                    if (timestampedPath != null) {
                        android.util.Log.d("UnifiedFaceCamera", "Timestamp added successfully: $timestampedPath")
                        result.success(timestampedPath)
                    } else {
                        android.util.Log.e("UnifiedFaceCamera", "Timestamping failed for path: $path")
                        result.error("TIMESTAMP_FAILED", "Failed to add timestamp to image", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "Path is null", null)
                }
            }
            "checkCameraPermission" -> {
                result.success(checkPermission())
            }
            "requestCameraPermission" -> {
                requestPermission(result)
            }
            "checkLocationPermission" -> {
                result.success(checkLocationPermission())
            }
            "requestLocationPermission" -> {
                requestLocationPermission(result)
            }
            "getLocation" -> {
                val loc = getLastKnownLocation()
                if (loc != null) {
                    result.success(mapOf("latitude" to loc.latitude, "longitude" to loc.longitude))
                } else {
                    result.success(null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun checkPermission(): Boolean {
        val act = activity ?: return false
        return ContextCompat.checkSelfPermission(
            act,
            android.Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(result: Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity is not available", null)
            return
        }

        if (checkPermission()) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            act,
            arrayOf(android.Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST_CODE
        )
    }

    private fun checkLocationPermission(): Boolean {
        val act = activity ?: return false
        return ContextCompat.checkSelfPermission(
            act,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
            act,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationPermission(result: Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity is not available", null)
            return
        }

        if (checkLocationPermission()) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            act,
            arrayOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            LOCATION_PERMISSION_REQUEST_CODE
        )
    }

    private fun getLastKnownLocation(): Location? {
        val act = activity ?: return null
        val locationManager = act.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        val providers = locationManager.getProviders(true)
        var bestLocation: Location? = null
        for (provider in providers) {
            try {
                val l = locationManager.getLastKnownLocation(provider) ?: continue
                if (bestLocation == null || l.accuracy < bestLocation.accuracy) {
                    bestLocation = l
                }
            } catch (e: SecurityException) {
                // Permission not granted
            }
        }
        return bestLocation
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            return true
        } else if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && (grantResults[0] == PackageManager.PERMISSION_GRANTED || (grantResults.size > 1 && grantResults[1] == PackageManager.PERMISSION_GRANTED))
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            return true
        }
        return false
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
