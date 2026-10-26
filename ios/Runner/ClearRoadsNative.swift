import CoreMotion
import Flutter
import Foundation

/// Queue of Siri requests. App Intents run before Flutter is guaranteed to be
/// up (cold launch), so requests are persisted and Flutter drains them.
final class SiriDraftInbox {
  static let shared = SiriDraftInbox()
  static let didEnqueue = Notification.Name("ClearRoadsSiriDraftEnqueued")

  private let key = "clear_roads.pending_siri_requests"
  private let defaults = UserDefaults.standard

  func enqueue(hazard: String?, details: String?, action: String) {
    var pending = defaults.array(forKey: key) as? [[String: Any]] ?? []
    var entry: [String: Any] = [
      "action": action,
      "createdAt": Date().timeIntervalSince1970 * 1000,
    ]
    if let hazard = hazard { entry["hazard"] = hazard }
    if let details = details, !details.isEmpty { entry["details"] = details }
    pending.append(entry)
    defaults.set(pending, forKey: key)
    NotificationCenter.default.post(name: SiriDraftInbox.didEnqueue, object: nil)
  }

  func drain() -> [[String: Any]] {
    let pending = defaults.array(forKey: key) as? [[String: Any]] ?? []
    defaults.removeObject(forKey: key)
    return pending
  }
}

/// Bridges Siri requests and CoreMotion driving detection to Flutter.
///
/// Channels:
///  - `clear_roads/siri` (method): `takePending` -> [request]; native calls
///    `pendingAvailable` when a new Siri request arrives while running.
///  - `clear_roads/motion` (method): `isAvailable` -> Bool.
///  - `clear_roads/motion_events` (event): activity updates
///    `{automotive, stationary, walking, running, cycling, confidence}`.
final class ClearRoadsNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let siriChannel: FlutterMethodChannel
  private let motionManager = CMMotionActivityManager()
  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  init(siriChannel: FlutterMethodChannel) {
    self.siriChannel = siriChannel
    super.init()
    observer = NotificationCenter.default.addObserver(
      forName: SiriDraftInbox.didEnqueue, object: nil, queue: .main
    ) { [weak self] _ in
      self?.siriChannel.invokeMethod("pendingAvailable", arguments: nil)
    }
  }

  deinit {
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let siri = FlutterMethodChannel(name: "clear_roads/siri", binaryMessenger: messenger)
    let motion = FlutterMethodChannel(name: "clear_roads/motion", binaryMessenger: messenger)
    let motionEvents = FlutterEventChannel(name: "clear_roads/motion_events", binaryMessenger: messenger)

    let instance = ClearRoadsNativePlugin(siriChannel: siri)
    registrar.addMethodCallDelegate(instance, channel: siri)
    registrar.addMethodCallDelegate(instance, channel: motion)
    motionEvents.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePending":
      result(SiriDraftInbox.shared.drain())
    case "isAvailable":
      result(CMMotionActivityManager.isActivityAvailable())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: FlutterStreamHandler (motion activity)

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CMMotionActivityManager.isActivityAvailable() else {
      return FlutterError(code: "unavailable", message: "Motion activity is not available on this device", details: nil)
    }
    eventSink = events
    motionManager.startActivityUpdates(to: .main) { [weak self] activity in
      guard let activity = activity, let sink = self?.eventSink else { return }
      sink([
        "automotive": activity.automotive,
        "stationary": activity.stationary,
        "walking": activity.walking,
        "running": activity.running,
        "cycling": activity.cycling,
        "confidence": activity.confidence.rawValue,  // 0 low, 1 medium, 2 high
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motionManager.stopActivityUpdates()
    eventSink = nil
    return nil
  }
}
