import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let picker = FlutterMethodChannel(
      name: "wifi_apk/floor_plan_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    picker.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickImage" || call.method == "pickProject" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let window = self else {
        result(FlutterError(code: "window_missing", message: "No active window", details: nil))
        return
      }
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      let isProject = call.method == "pickProject"
      panel.allowedFileTypes = isProject
        ? ["wifimap"]
        : ["png", "jpg", "jpeg", "webp"]
      panel.beginSheetModal(for: window) { response in
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        do {
          let data = try Data(contentsOf: url, options: .mappedIfSafe)
          let byteLimit = isProject ? 35 * 1024 * 1024 : 25 * 1024 * 1024
          guard !data.isEmpty, data.count <= byteLimit else {
            throw NSError(
              domain: "wifi_apk.floor_plan_picker",
              code: 1,
              userInfo: [NSLocalizedDescriptionKey: "Selected file is empty or too large"])
          }
          result([
            "name": url.lastPathComponent,
            "bytes": FlutterStandardTypedData(bytes: data),
          ])
        } catch {
          result(FlutterError(
            code: "image_read_failed",
            message: error.localizedDescription,
            details: nil))
        }
      }
    }

    super.awakeFromNib()
  }
}
