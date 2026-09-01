import Foundation

/// TAKT: Zentrale Definition des App-Datenordners in Application Support.
/// Der Ordner heisst "wertwandler-takt" (statt dem Dayflow-Erbe "Dayflow");
/// StoragePathMigrator verschiebt bestehende Daten beim ersten Start.
enum StoragePaths {
  static let folderName = "wertwandler-takt"

  static var appSupportBase: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupport.appendingPathComponent(folderName, isDirectory: true)
  }
}
