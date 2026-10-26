import AppIntents
import Foundation

/// Hazard categories exposed to Siri / Shortcuts. Raw values must match
/// `HazardType.id` on the Dart side (lib/models/hazard.dart).
@available(iOS 16.0, *)
enum HazardKind: String, AppEnum {
  case deadAnimal
  case fallenTree
  case snowIce
  case pothole
  case debris
  case other

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Road hazard"

  static var caseDisplayRepresentations: [HazardKind: DisplayRepresentation] = [
    .deadAnimal: DisplayRepresentation(
      title: "Dead animal",
      synonyms: ["animal carcass", "carcass", "dead deer", "deer", "roadkill"]),
    .fallenTree: DisplayRepresentation(
      title: "Fallen tree",
      synonyms: ["tree", "tree down", "downed tree", "branch", "fallen branch"]),
    .snowIce: DisplayRepresentation(
      title: "Snow or ice",
      synonyms: ["snow", "ice", "black ice", "unplowed road", "icy road"]),
    .pothole: DisplayRepresentation(title: "Pothole", synonyms: ["hole", "pot hole"]),
    .debris: DisplayRepresentation(title: "Debris", synonyms: ["rocks", "trash", "object in road"]),
    .other: DisplayRepresentation(title: "Other hazard", synonyms: ["something else", "hazard"]),
  ]

  var spokenName: String {
    switch self {
    case .deadAnimal: return "dead animal"
    case .fallenTree: return "fallen tree"
    case .snowIce: return "snow or ice"
    case .pothole: return "pothole"
    case .debris: return "debris"
    case .other: return "road hazard"
    }
  }
}

/// "Hey Siri, report a fallen tree in Clear Roads"
/// Siri asks for the hazard type if it wasn't spoken, then opens the app,
/// which captures GPS immediately and saves the report as a draft.
@available(iOS 16.0, *)
struct ReportHazardIntent: AppIntent {
  static var title: LocalizedStringResource = "Report Road Hazard"
  static var description = IntentDescription(
    "Hands-free: saves a draft road-hazard report at your current location. Submit it later, once you've stopped driving.")
  static var openAppWhenRun: Bool = true

  @Parameter(
    title: "Hazard",
    requestValueDialog: IntentDialog("What did you see? A dead animal, a fallen tree, or snow and ice?"))
  var hazard: HazardKind

  @Parameter(title: "Details")
  var details: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Report \(\.$hazard)") {
      \.$details
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    SiriDraftInbox.shared.enqueue(hazard: hazard.rawValue, details: details, action: "draft")
    return .result(
      dialog: IntentDialog("Got it. Saving a \(hazard.spokenName) draft. Submit it once you've safely stopped."))
  }
}

/// "Hey Siri, show my road reports" – jumps to the drafts list.
@available(iOS 16.0, *)
struct ShowDraftsIntent: AppIntent {
  static var title: LocalizedStringResource = "Show Draft Road Reports"
  static var description = IntentDescription("Opens your saved drafts so you can review and submit them.")
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    SiriDraftInbox.shared.enqueue(hazard: nil, details: nil, action: "showDrafts")
    return .result()
  }
}

@available(iOS 16.0, *)
struct ClearRoadsShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ReportHazardIntent(),
      phrases: [
        "Report \(\.$hazard) in \(.applicationName)",
        "Report \(\.$hazard) with \(.applicationName)",
        "Report a hazard in \(.applicationName)",
        "Report a road hazard with \(.applicationName)",
        "\(.applicationName) report",
      ],
      shortTitle: "Report Hazard",
      systemImageName: "exclamationmark.triangle.fill")
    AppShortcut(
      intent: ShowDraftsIntent(),
      phrases: [
        "Show my \(.applicationName) drafts",
        "Show my road reports in \(.applicationName)",
      ],
      shortTitle: "My Drafts",
      systemImageName: "tray.full.fill")
  }
}
