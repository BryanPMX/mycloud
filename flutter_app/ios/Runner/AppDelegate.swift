import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "live.mynube.app/private_uploads", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "protect", let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
          result(FlutterMethodNotImplemented); return
        }
        var url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(base.standardizedFileURL.path + "/") else {
          result(FlutterError(code: "INVALID_PATH", message: "Invalid private upload path", details: nil)); return
        }
        do {
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
          try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
          result(nil)
        } catch {
          result(FlutterError(code: "PROTECTION_FAILED", message: "Private upload storage could not be prepared", details: nil))
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
