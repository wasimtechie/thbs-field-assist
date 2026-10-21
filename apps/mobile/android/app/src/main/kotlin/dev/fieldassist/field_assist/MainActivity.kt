package dev.fieldassist.field_assist

import android.content.Context
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import androidx.lifecycle.Lifecycle
import java.time.Instant
import java.io.File
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import android.os.PowerManager
import android.os.StatFs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
  private var labelRecognizer: TextRecognizer? = null
  private var labelResult: MethodChannel.Result? = null
  private var labelGeneration = 0
  private fun clearLabel(): MethodChannel.Result? {
    val pending = labelResult; labelResult = null; labelGeneration++
    labelRecognizer?.close(); labelRecognizer = null
    return pending
  }
  private fun recognizeLabel(path: String?, result: MethodChannel.Result) {
    if (labelResult != null) { result.error("OCR_BUSY", "A label is already being read.", null); return }
    val file = path?.let { File(it).canonicalFile }
    if (file == null || !file.path.startsWith(cacheDir.canonicalPath + File.separator) || !file.isFile || file.length() > 12582912) {
      result.error("INVALID_IMAGE", "Retake the label photo and try again.", null); return
    }
    try {
      val image = InputImage.fromFilePath(this, Uri.fromFile(file))
      val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
      labelRecognizer = recognizer; labelResult = result
      val generation = labelGeneration
      recognizer.process(image).addOnSuccessListener { text ->
        if (generation == labelGeneration) clearLabel()?.success(text.text.take(32000))
      }.addOnFailureListener {
        if (generation == labelGeneration) clearLabel()?.error("OCR_FAILED", "The label could not be read. Retake a sharper photo or enter the details manually.", null)
      }
    } catch (_: Exception) { clearLabel(); result.error("OCR_FAILED", "The label photo could not be opened. Retake it and retry.", null) }
  }
  private var locationResult: MethodChannel.Result? = null
  private val locationHandler = Handler(Looper.getMainLooper())
  private val locationSignals = mutableListOf<CancellationSignal>()
  private var locationGeneration = 0
  private var locationPermissionOnly = false
  private var requestingLocationPermission = false
  private var locationAfterPermission = false
  private val locationTimeout = Runnable { failLocation("LOCATION_TIMEOUT", "No fresh location was found. Move outdoors and retry. Your draft is saved.") }
  private fun hasLocationPermission() = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
  private fun clearLocation(): MethodChannel.Result? {
    val result = locationResult
    locationResult = null
    locationAfterPermission = false
    locationGeneration++
    locationHandler.removeCallbacks(locationTimeout)
    locationSignals.forEach { it.cancel() }
    locationSignals.clear()
    return result
  }
  private fun failLocation(code: String, message: String) { clearLocation()?.error(code, message, null) }
  private fun captureLocation(result: MethodChannel.Result, permissionOnly: Boolean = false) {
    if (locationResult != null || requestingLocationPermission) { result.error("LOCATION_BUSY", "A location request is already in progress.", null); return }
    locationResult = result
    locationPermissionOnly = permissionOnly
    locationHandler.postDelayed(locationTimeout, 60000)
    if (hasLocationPermission()) continueLocationRequest()
    else {
      val preferences = getSharedPreferences("location_permission", Context.MODE_PRIVATE)
      if (preferences.getBoolean("requested", false) &&
        !shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) &&
        !shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION)) {
        failLocation("PERMISSION_DENIED", "Location access is blocked. Open app permissions and allow location. Your draft is saved.")
        return
      }
      preferences.edit().putBoolean("requested", true).apply()
      requestingLocationPermission = true
      requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 6401)
    }
  }
  private fun continueLocationRequest() {
    if (locationPermissionOnly) clearLocation()?.success(null)
    else requestLocationFix()
  }
  private fun requestLocationFix() {
    if (locationResult == null) return
    val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
    if (!manager.isLocationEnabled) { failLocation("LOCATION_DISABLED", "Switch on device Location and retry. Your draft is saved."); return }
    val precise = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    val providers = listOf(LocationManager.FUSED_PROVIDER, LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
      .filter { manager.allProviders.contains(it) && manager.isProviderEnabled(it) && (precise || it != LocationManager.GPS_PROVIDER) }
    if (providers.isEmpty()) { failLocation("LOCATION_UNAVAILABLE", "No location provider is available. Enable precise location or network location and retry."); return }
    val generation = locationGeneration
    var remaining = providers.size
    for (provider in providers) {
      val signal = CancellationSignal()
      locationSignals.add(signal)
      try {
        manager.getCurrentLocation(provider, signal, mainExecutor) { location ->
          if (generation != locationGeneration || locationResult == null) return@getCurrentLocation
          remaining--
          val age = location?.let { (SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) / 1000000 }
          if (location != null && location.hasAccuracy() && location.accuracy >= 0 && age != null && age in 0..60000) {
            clearLocation()?.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude,
              "accuracyMeters" to location.accuracy.toDouble(), "capturedAt" to Instant.ofEpochMilli(location.time).toString(), "isMocked" to location.isMock))
          } else if (remaining == 0) failLocation("LOCATION_UNAVAILABLE", "A fresh location is unavailable. Move outdoors and retry. Your draft is saved.")
        }
      } catch (_: SecurityException) {
        failLocation("PERMISSION_DENIED", "Allow Field Assist location access in App permissions, then retry. Your draft is saved.")
        return
      } catch (_: IllegalArgumentException) {
        remaining--
        if (remaining == 0) failLocation("LOCATION_UNAVAILABLE", "Location is unavailable. Check device location settings and retry.")
      }
    }
  }
  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == 6401) {
      requestingLocationPermission = false
      if (locationResult == null) return
      if (hasLocationPermission()) {
        // OEM permission activities can temporarily stop the host Activity.
        // Never acquire a fix in the background; finish on its resumed screen.
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) continueLocationRequest()
        else locationAfterPermission = true
      }
      else failLocation("PERMISSION_DENIED", "Location access is required to confirm. Allow it in App permissions and retry. Your draft is saved.")
    }
  }
  override fun onPostResume() {
    super.onPostResume()
    if (locationAfterPermission && locationResult != null) {
      locationAfterPermission = false
      continueLocationRequest()
    }
  }
  override fun onStop() {
    clearLabel()?.error("OCR_CANCELLED", "Label scanning stopped when the app left the foreground. Your existing answers are saved.", null)
    if (!requestingLocationPermission) failLocation("LOCATION_CANCELLED", "Location capture stopped when the app left the foreground. Unlock and retry. Your draft is saved.")
    super.onStop()
  }
  override fun onDestroy() {
    failLocation("LOCATION_CANCELLED", "Location capture stopped. Reopen the app and retry. Your draft is saved.")
    super.onDestroy()
  }
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "field_assist/label_ocr").setMethodCallHandler { call, result ->
      when (call.method) {
        "recognize" -> recognizeLabel(call.argument<String>("path"), result)
        "cancel" -> { clearLabel()?.error("OCR_CANCELLED", "Label scan cancelled.", null); result.success(null) }
        else -> result.notImplemented()
      }
    }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "field_assist/location").setMethodCallHandler { call, result ->
      when (call.method) {
        "prepare" -> captureLocation(result, permissionOnly = true)
        "capture" -> captureLocation(result)
        "cancel" -> { failLocation("LOCATION_CANCELLED", "Location capture was cancelled. Your draft is saved."); result.success(null) }
        "openSettings" -> {
          val intent = if (call.argument<Boolean>("deviceLocation") == true) Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
          startActivity(intent); result.success(null)
        }
        else -> result.notImplemented()
      }
    }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "field_assist/security").setMethodCallHandler { call, result ->
      when (call.method) {
        "availableStorage" -> result.success(StatFs(filesDir.absolutePath).availableBytes)
        "powerConstrained" -> {
          val power = getSystemService(Context.POWER_SERVICE) as PowerManager
          result.success(power.isPowerSaveMode || power.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE)
        }
        else -> result.notImplemented()
      }
    }
  }
}
