//
//  OnboardingStepMigration.swift
//  TAKT
//
//  Wizard step order + legacy UserDefaults migration for the TAKT-era
//  onboarding. Kept so existing installs that never finished the old wizard
//  still migrate correctly to the TAKT onboarding (didOnboard flag).
//

import Foundation

/// Wizard step order (legacy TAKT onboarding steps)
enum OnboardingStep: Int, CaseIterable {
  case introVideo, roleSelection, downloadReason, referral, preferences, llmSelection, llmSetup,
    categories, categoryColors, screen, completion

  var analyticsName: String {
    switch self {
    case .introVideo:
      return "intro_video"
    case .roleSelection:
      return "role_selection"
    case .downloadReason:
      return "download_reason"
    case .referral:
      return "referral"
    case .preferences:
      return "preferences"
    case .llmSelection:
      return "llm_selection"
    case .llmSetup:
      return "llm_setup"
    case .categories:
      return "categories"
    case .categoryColors:
      return "category_colors"
    case .screen:
      return "screen_recording"
    case .completion:
      return "completion"
    }
  }

  static func hasPassedScreenRecordingStep(rawValue: Int) -> Bool {
    guard let step = OnboardingStep(rawValue: rawValue) else { return false }
    return step.rawValue > OnboardingStep.screen.rawValue
  }

  mutating func next() { self = OnboardingStep(rawValue: rawValue + 1)! }
}

enum OnboardingStepMigration {
  static let schemaVersionKey = "onboardingStepSchemaVersion"
  private static let onboardingStepKey = "onboardingStep"
  static let currentVersion = 5

  @discardableResult
  static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Int {
    let storedVersion = defaults.integer(forKey: schemaVersionKey)
    let rawValue = defaults.integer(forKey: onboardingStepKey)
    guard storedVersion < currentVersion else {
      return rawValue
    }

    var migratedValue = rawValue

    // v0 → v1: reorder steps
    if storedVersion < 1 {
      migratedValue = migrateV0toV1(migratedValue)
    }

    // v1 → v2: welcome/howItWorks replaced by introVideo/roleSelection/preferences
    if storedVersion < 2 {
      migratedValue = migrateV1toV2(migratedValue)
    }

    // v2 → v3: insert referral after role selection
    if storedVersion < 3 {
      migratedValue = migrateV2toV3(migratedValue)
    }

    // v3 → v4: insert categoryColors after categories
    if storedVersion < 4 {
      migratedValue = migrateV3toV4(migratedValue)
    }

    // v4 → v5: insert downloadReason after roleSelection
    if storedVersion < 5 {
      migratedValue = migrateV4toV5(migratedValue)
    }

    defaults.set(migratedValue, forKey: onboardingStepKey)
    defaults.set(currentVersion, forKey: schemaVersionKey)
    return migratedValue
  }

  static func restoredStep(defaults: UserDefaults = .standard) -> OnboardingStep {
    OnboardingStep(rawValue: migrateIfNeeded(defaults: defaults)) ?? .introVideo
  }

  static func migrateV0toV1(_ rawValue: Int) -> Int {
    switch rawValue {
    case 0: return 0  // welcome
    case 1: return 1  // how it works
    case 2: return 5  // legacy screen step moves after categories
    case 3: return 2  // llm selection
    case 4: return 3  // llm setup
    case 5: return 4  // categories
    case 6: return 6  // completion
    default: return 0
    }
  }

  static func migrateV1toV2(_ rawValue: Int) -> Int {
    switch rawValue {
    case 0: return 0  // welcome → introVideo (restart from beginning)
    case 1: return 0  // howItWorks → introVideo (restart from beginning)
    case 2: return 3  // llmSelection → llmSelection
    case 3: return 4  // llmSetup → llmSetup
    case 4: return 5  // categories → categories
    case 5: return 6  // screen → screen
    case 6: return 7  // completion → completion
    default: return 0
    }
  }

  static func migrateV2toV3(_ rawValue: Int) -> Int {
    switch rawValue {
    case 0: return 0  // introVideo → introVideo
    case 1: return 1  // roleSelection → roleSelection
    case 2: return 3  // preferences → preferences
    case 3: return 4  // llmSelection → llmSelection
    case 4: return 5  // llmSetup → llmSetup
    case 5: return 6  // categories → categories
    case 6: return 7  // screen → screen
    case 7: return 8  // completion → completion
    default: return 0
    }
  }

  static func migrateV3toV4(_ rawValue: Int) -> Int {
    switch rawValue {
    case 0...6: return rawValue  // unchanged through categories
    case 7: return 8  // screen → screen
    case 8: return 9  // completion → completion
    default: return 0
    }
  }

  static func migrateV4toV5(_ rawValue: Int) -> Int {
    switch rawValue {
    case 0...1: return rawValue  // unchanged through roleSelection
    case 2...9: return rawValue + 1  // steps after roleSelection shift forward
    default: return 0
    }
  }

  // Keep for testing compatibility
  static func migrateRawValue(_ rawValue: Int) -> Int {
    migrateV4toV5(migrateV3toV4(migrateV2toV3(migrateV1toV2(migrateV0toV1(rawValue)))))
  }
}
