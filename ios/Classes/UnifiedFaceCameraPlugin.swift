import Flutter
import UIKit
import AVFoundation
import CoreLocation

public class UnifiedFaceCameraPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
  private var locationManager: CLLocationManager?
  private var pendingLocationResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "unified_face_camera", binaryMessenger: registrar.messenger())
    let instance = UnifiedFaceCameraPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "addTimestamp":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is null or invalid", details: nil))
        return
      }
      let latitude = args["latitude"] as? Double
      let longitude = args["longitude"] as? Double
      if let timestampedPath = addTimestamp(to: path, latitude: latitude, longitude: longitude) {
        result(timestampedPath)
      } else {
        result(FlutterError(code: "TIMESTAMP_FAILED", message: "Failed to add timestamp to image", details: nil))
      }

    case "checkCameraPermission":
      result(checkCameraPermission())

    case "requestCameraPermission":
      requestCameraPermission(result: result)

    case "checkLocationPermission":
      result(checkLocationPermission())

    case "requestLocationPermission":
      requestLocationPermission(result: result)

    case "getLocation":
      if let coordinate = getLatLng() {
        result(["latitude": coordinate.latitude, "longitude": coordinate.longitude])
      } else {
        result(nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Watermark

  /// Draws a date/time stamp and location onto the JPEG at `imagePath` and overwrites it.
  /// Returns the path on success, nil on failure.
  private func addTimestamp(to imagePath: String, latitude: Double?, longitude: Double?) -> String? {
    let fileURL = URL(fileURLWithPath: imagePath)
    guard FileManager.default.fileExists(atPath: imagePath),
          let imageData = try? Data(contentsOf: fileURL),
          let uiImage = UIImage(data: imageData) else { return nil }

    let formatter = DateFormatter()
    formatter.dateFormat = "dd-MM-yyyy hh:mm a"
    formatter.locale = Locale(identifier: "en_US")
    let timestamp = formatter.string(from: Date())

    let locationText: String
    if let lat = latitude, let lng = longitude {
      locationText = String(format: "Lat: %.4f, Long: %.4f", lat, lng)
    } else {
      locationText = "Location: Not Available"
    }

    let scale = uiImage.scale
    UIGraphicsBeginImageContextWithOptions(uiImage.size, false, scale)
    defer { UIGraphicsEndImageContext() }

    uiImage.draw(at: .zero)

    let fontSize = uiImage.size.width / 22.0
    let attrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
      .foregroundColor: UIColor.white,
      .shadow: {
        let s = NSShadow()
        s.shadowColor = UIColor.black
        s.shadowOffset = CGSize(width: 2, height: 2)
        s.shadowBlurRadius = 4
        return s
      }()
    ]

    let tsSize = (timestamp as NSString).size(withAttributes: attrs)
    let locSize = (locationText as NSString).size(withAttributes: attrs)

    let maxTextWidth = max(tsSize.width, locSize.width)
    let lineHeight = tsSize.height
    let spacing = lineHeight * 0.4
    let totalTextHeight = lineHeight * 2 + spacing

    let padding = uiImage.size.width * 0.02
    let textX = uiImage.size.width - maxTextWidth - padding * 2
    let textY = uiImage.size.height - totalTextHeight - padding * 2

    // Semi-transparent background
    let bgRect = CGRect(
      x: textX - padding,
      y: textY - padding,
      width: maxTextWidth + padding * 3,
      height: totalTextHeight + padding * 2
    )
    UIColor(white: 0, alpha: 0.63).setFill()
    UIBezierPath(roundedRect: bgRect, cornerRadius: 4).fill()

    (timestamp as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: attrs)
    (locationText as NSString).draw(at: CGPoint(x: textX, y: textY + lineHeight + spacing), withAttributes: attrs)

    guard let resultImage = UIGraphicsGetImageFromCurrentImageContext(),
          let jpegData = resultImage.jpegData(compressionQuality: 0.92) else { return nil }

    do {
      try jpegData.write(to: fileURL, options: .atomic)
    } catch {
      return nil
    }
    return imagePath
  }

  // MARK: - Permissions

  private func checkCameraPermission() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    default: return false
    }
  }

  private func requestCameraPermission(result: @escaping FlutterResult) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      result(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { result(granted) }
      }
    default:
      result(false)
    }
  }

  private func checkLocationPermission() -> Bool {
    let status = CLLocationManager.authorizationStatus()
    return status == .authorizedWhenInUse || status == .authorizedAlways
  }

  private func requestLocationPermission(result: @escaping FlutterResult) {
    if locationManager == nil {
      locationManager = CLLocationManager()
      locationManager?.delegate = self
    }
    let status = CLLocationManager.authorizationStatus()
    switch status {
    case .authorizedWhenInUse, .authorizedAlways:
      result(true)
    case .notDetermined:
      pendingLocationResult = result
      locationManager?.requestWhenInUseAuthorization()
    default:
      result(false)
    }
  }

  private func getLatLng() -> CLLocationCoordinate2D? {
    if locationManager == nil {
      locationManager = CLLocationManager()
      locationManager?.delegate = self
    }
    if checkLocationPermission() {
      if let location = locationManager?.location {
        return location.coordinate
      }
    }
    return nil
  }

  // MARK: - CLLocationManagerDelegate

  public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if status != .notDetermined {
      if let res = pendingLocationResult {
        res(status == .authorizedWhenInUse || status == .authorizedAlways)
        pendingLocationResult = nil
      }
    }
  }
}
