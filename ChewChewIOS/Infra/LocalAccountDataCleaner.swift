import Foundation

protocol LocalAccountDataClearing {
    func clear()
}

/// 서버 계정 삭제가 성공한 뒤에만 실행하는 계정 단위 로컬 개인정보 정리기.
struct LocalAccountDataCleaner: LocalAccountDataClearing {
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let calibrationUploadsDirectory: URL

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        calibrationUploadsDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.calibrationUploadsDirectory = calibrationUploadsDirectory
            ?? CalibrationArtifactUploadQueue.defaultRootDirectory(fileManager: fileManager)
    }

    func clear() {
        UserDefaultsChewProfileStore(defaults: defaults).clear()
        MealReminderSettings.clear(from: defaults)

        guard fileManager.fileExists(atPath: calibrationUploadsDirectory.path) else { return }
        try? fileManager.removeItem(at: calibrationUploadsDirectory)
    }
}
