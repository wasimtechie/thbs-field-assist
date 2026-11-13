import Flutter
import UIKit
import CoreLocation
import Vision
import Security
import AVFAudio

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let reportLocation = ReportLocationCapture()
  private let labelRecognition = CableLabelRecognition()
  private let voicePlayback = VoicePromptPlayback()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FieldAssistSecurity") else { return }
    let channel = FlutterMethodChannel(name: "field_assist/security", binaryMessenger: registrar.messenger())
    let locationChannel = FlutterMethodChannel(name: "field_assist/location", binaryMessenger: registrar.messenger())
    let labelChannel = FlutterMethodChannel(name: "field_assist/label_ocr", binaryMessenger: registrar.messenger())
    let voiceChannel = FlutterMethodChannel(name: "field_assist/voice_playback", binaryMessenger: registrar.messenger())
    voiceChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "VOICE_CLOSED", message: "Voice playback is unavailable.", details: nil)); return }
      self.voicePlayback.handle(call, result: result)
    }
    labelChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "recognize": self.labelRecognition.recognize((call.arguments as? [String: Any])?["path"] as? String, result: result)
      case "cancel": self.labelRecognition.cancel(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    locationChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "prepare": self.reportLocation.capture(result, permissionOnly: true)
      case "capture": self.reportLocation.capture(result)
      case "cancel": self.reportLocation.cancel(); result(nil)
      case "openSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else { result(nil); return }
        UIApplication.shared.open(url); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "writeAccountSecret", "deleteAccountSecret":
        AccountKeychain.mutate(call, result: result)
      case "powerConstrained":
        let info = ProcessInfo.processInfo
        result(info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical)
      case "availableStorage":
        do {
          let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
          result((attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
        } catch { result(FlutterError(code: "STORAGE_UNAVAILABLE", message: "Available storage could not be checked.", details: nil)) }
      case "excludeFromBackup":
        guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
          result(FlutterError(code: "INVALID_PATH", message: "An account directory is required.", details: nil)); return
        }
        do {
          var url = URL(fileURLWithPath: path)
          let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].standardizedFileURL.path
          guard url.standardizedFileURL.path.hasPrefix(root + "/") else {
            result(FlutterError(code: "INVALID_PATH", message: "Only application support files can be excluded.", details: nil)); return
          }
          var values = URLResourceValues(); values.isExcludedFromBackup = true
          try url.setResourceValues(values); result(nil)
        } catch { result(FlutterError(code: "BACKUP_EXCLUSION_FAILED", message: "Could not protect local account data from backup.", details: nil)) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Short, in-memory TTS prompts use the conversation's AVAudioSession. The Dart
/// owner changes category only after playback/capture has fully stopped. There
/// is no deferred engine pause worker left to race the next microphone turn.
private final class VoicePromptPlayback: NSObject, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?
  private var playbackId: String?
  private var pending: FlutterResult?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if targetEnvironment(simulator)
    // Read-only timing probe. Tests observe the native playback cursor instead
    // of treating the Dart animation meter as an audible-start timestamp.
    if call.method == "diagnosticPlaybackPosition" {
      result(["playing": player?.isPlaying ?? false,
              "seconds": player?.currentTime ?? 0])
      return
    }
    #endif
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? String, !id.isEmpty else {
      result(FlutterError(code: "INVALID_AUDIO", message: "A voice playback ID is required.", details: nil)); return
    }
    switch call.method {
    case "play":
      guard let wav = args["wav"] as? FlutterStandardTypedData,
        wav.data.count >= 44, wav.data.count <= 33554432 else {
        result(FlutterError(code: "INVALID_AUDIO", message: "A valid voice prompt is required.", details: nil)); return
      }
      finish(false)
      do {
        let output = try AVAudioPlayer(data: wav.data)
        output.delegate = self
        output.volume = min(1, max(0, (args["volume"] as? NSNumber)?.floatValue ?? 1))
        player = output; playbackId = id; pending = result
        guard output.prepareToPlay(), output.play() else {
          finish(FlutterError(code: "VOICE_PLAYBACK_FAILED", message: "Voice playback could not start. Retry the voice assistant.", details: nil)); return
        }
      } catch {
        // If decoding failed before ownership was assigned there is no pending
        // callback for finish() to resolve.
        if pending != nil {
          finish(FlutterError(code: "VOICE_PLAYBACK_FAILED", message: "Voice playback could not start. Retry the voice assistant.", details: nil))
        } else {
          result(FlutterError(code: "VOICE_PLAYBACK_FAILED", message: "Voice playback could not start. Retry the voice assistant.", details: nil))
        }
      }
    case "stop":
      if playbackId == id { finish(false) }
      result(nil)
    case "volume":
      if playbackId == id {
        player?.volume = min(1, max(0, (args["volume"] as? NSNumber)?.floatValue ?? 1))
      }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func finish(_ value: Any) {
    let callback = pending
    pending = nil; playbackId = nil
    let output = player; player = nil
    output?.delegate = nil
    output?.stop()
    callback?(value)
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard self.player === player else { return }
    finish(flag)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard self.player === player else { return }
    finish(FlutterError(code: "VOICE_DECODE_FAILED", message: "Voice playback failed. Retry the voice assistant.", details: nil))
  }

  @objc private func backgrounded() { finish(false) }
}

/// Use only identity attributes in mutation queries. Never delete/recreate an
/// existing secret to update it: a failed update must retain its original value.
private enum AccountKeychain {
  static func mutate(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let key = args["key"] as? String, !key.isEmpty,
      let policy = args["accessibility"] as? String,
      ["unlocked", "unlocked_this_device"].contains(policy) else {
      result(FlutterError(code: "INVALID_SECRET_REQUEST", message: "Invalid secure storage request.", details: nil)); return
    }
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "flutter_secure_storage_service",
      kSecAttrAccount: key,
      kSecAttrSynchronizable: false,
    ]
    var status: OSStatus
    if call.method == "deleteAccountSecret" {
      status = SecItemDelete(query as CFDictionary)
      if status == errSecItemNotFound { status = errSecSuccess }
    } else {
      guard let value = args["value"] as? String else {
        result(FlutterError(code: "INVALID_SECRET_REQUEST", message: "A secure value is required.", details: nil)); return
      }
      let update: [CFString: Any] = [kSecValueData: Data(value.utf8)]
      status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
      if status == errSecItemNotFound {
        var item = query
        item[kSecValueData] = Data(value.utf8)
        item[kSecAttrAccessible] = policy == "unlocked_this_device"
          ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly : kSecAttrAccessibleWhenUnlocked
        status = SecItemAdd(item as CFDictionary, nil)
        // Another writer may have inserted the same identity in between.
        if status == errSecDuplicateItem {
          status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
      }
    }
    guard status == errSecSuccess else {
      result(FlutterError(code: "SECURE_STORAGE", message: "Secure account storage could not be updated (\(status)). Saved data is retained.", details: nil)); return
    }
    result(nil)
  }
}

private final class CableLabelRecognition {
  private var generation = 0
  private var pending: FlutterResult?
  private var request: VNRecognizeTextRequest?
  func cancel() {
    generation += 1; request?.cancel(); request = nil
    let result = pending; pending = nil
    result?(FlutterError(code: "OCR_CANCELLED", message: "Label scan cancelled. Existing answers are retained.", details: nil))
  }
  func recognize(_ path: String?, result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "OCR_BUSY", message: "A label is already being read.", details: nil)); return }
    guard let path else { result(FlutterError(code: "INVALID_IMAGE", message: "Retake the label photo.", details: nil)); return }
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath().path
    guard url.path.hasPrefix(temp + "/") || url.path.hasPrefix(cache + "/"),
      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 12582912 else {
      result(FlutterError(code: "INVALID_IMAGE", message: "Retake the label photo and retry.", details: nil)); return
    }
    pending = result
    let current = generation
    let work = VNRecognizeTextRequest()
    work.recognitionLevel = .accurate
    work.usesLanguageCorrection = false // Preserve serial numbers; don't spell-correct identifiers.
    work.recognitionLanguages = ["en-US"]
    request = work
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let output: Any
      do {
        try VNImageRequestHandler(url: url).perform([work])
        output = String((work.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").prefix(32000))
      } catch { output = FlutterError(code: "OCR_FAILED", message: "The label could not be read. Retake a sharper photo or enter details manually.", details: nil) }
      DispatchQueue.main.async {
        guard let self, current == self.generation else { return }
        let callback = self.pending; self.pending = nil; self.request = nil
        callback?(output)
      }
    }
  }
}

/// Retained for the engine lifetime; a manager is created per foreground request
/// so a cancelled callback cannot complete a later report's capture.
private final class ReportLocationCapture: NSObject, CLLocationManagerDelegate {
  private var permissionOnly = false
  private var manager: CLLocationManager?
  private var pending: FlutterResult?
  private var timeout: DispatchWorkItem?
  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
  }
  func capture(_ result: @escaping FlutterResult, permissionOnly: Bool = false) {
    guard pending == nil else { result(FlutterError(code: "LOCATION_BUSY", message: "A location request is already in progress.", details: nil)); return }
    let manager = CLLocationManager()
    self.manager = manager
    self.permissionOnly = permissionOnly
    pending = result
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    let work = DispatchWorkItem { [weak self] in self?.finish(error: "LOCATION_TIMEOUT", message: "No fresh location was found. Check Location Services, move outdoors and retry. Your draft is saved.") }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    authorize(manager)
  }
  private func authorize(_ manager: CLLocationManager) {
    guard self.manager === manager, pending != nil else { return }
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      if permissionOnly { complete(nil) } else { manager.requestLocation() }
    case .denied: finish(error: "PERMISSION_DENIED", message: "Enable Location Services and allow Field Assist location access in Settings. Then unlock and retry. Your draft is saved.")
    case .restricted: finish(error: "PERMISSION_RESTRICTED", message: "Location access is restricted by device settings. Your draft is saved; ask the device administrator to allow location.")
    @unknown default: finish(error: "LOCATION_UNAVAILABLE", message: "Location is unavailable. Your draft is saved.")
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorize(manager) }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard self.manager === manager, pending != nil else { return }
    guard let location = locations.last, location.horizontalAccuracy >= 0,
      Date().timeIntervalSince(location.timestamp) >= -30,
      Date().timeIntervalSince(location.timestamp) <= 60 else {
      finish(error: "LOCATION_UNAVAILABLE", message: "A fresh location is unavailable. Move outdoors and retry. Your draft is saved."); return
    }
    var simulated = false
    if #available(iOS 15.0, *) { simulated = location.sourceInformation?.isSimulatedBySoftware ?? false }
    #if targetEnvironment(simulator)
    simulated = true
    #endif
    let value: [String: Any] = ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
      "accuracyMeters": location.horizontalAccuracy, "capturedAt": ISO8601DateFormatter().string(from: location.timestamp), "isMocked": simulated]
    complete(value)
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard self.manager === manager else { return }
    if (error as? CLError)?.code == .denied { finish(error: "PERMISSION_DENIED", message: "Enable Location Services and allow Field Assist location access in Settings. Your draft is saved.") }
    else { finish(error: "LOCATION_UNAVAILABLE", message: "Location is unavailable. Check Location Services, move outdoors and retry. Your draft is saved.") }
  }
  private func complete(_ value: Any?) {
    let result = pending
    pending = nil
    timeout?.cancel(); timeout = nil
    manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
    result?(value)
  }
  private func finish(error: String, message: String) { complete(FlutterError(code: error, message: message, details: nil)) }
  @objc private func backgrounded() { cancel() }
  func cancel() { finish(error: "LOCATION_CANCELLED", message: "Location capture stopped. Unlock and retry. Your draft is saved.") }
}
