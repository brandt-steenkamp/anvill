import Foundation

final class BrailleTranslator {

    enum TranslatorError: LocalizedError {
        case tablesFolderMissing
        case tableMissing(String)
        case translationFailed(String)

        var errorDescription: String? {
            switch self {
            case .tablesFolderMissing:
                return "tables folder not found in app bundle resources"
            case .tableMissing(let name):
                return "Braille table not found: \(name)"
            case .translationFailed(let details):
                return "Liblouis translation failed: \(details)"
            }
        }
    }

    private enum LouisMode {
        case forward
        case backward
    }

    private let tablesDir: URL

    init() {
        guard let tablesURL = Bundle.main.url(forResource: "tables", withExtension: nil) else {
            fatalError("tables folder not found in app bundle resources")
        }

        self.tablesDir = tablesURL

        // Deprecated, yes, but still useful for tables that include other tables.
        lou_setDataPath(tablesURL.path)
        print("Liblouis data path set to:", tablesURL.path)
    }

    // MARK: - Public API

    /// Forward translate: plain text -> braille
    func translate(text: String, tableName: String) -> String {
        runLouis(input: text, tableName: tableName, mode: .forward)
    }

    /// Back-translate: braille -> plain text
    /// Note: Typically you will use a .utb table here, not a .ctb.
    func backTranslate(braille: String, tableName: String) -> String {
        runLouis(input: braille, tableName: tableName, mode: .backward)
    }

    /// Round-trip check: text -> braille -> text
    func roundTripCheck(
        text: String,
        forwardTable: String,
        backwardTable: String
    ) -> (braille: String, back: String) {

        let braille = translate(text: text, tableName: forwardTable)
        let back = backTranslate(braille: braille, tableName: backwardTable)
        return (braille, back)
    }

    /// Optional helper: discover available tables to drive your pickers dynamically.
    func availableTableFiles() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tablesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "ctb" || ext == "utb"
            }
            .map { $0.lastPathComponent }
            .sorted()
    }

    // MARK: - Core engine

    private func runLouis(input: String, tableName: String, mode: LouisMode) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let tableURL = resolveTableURL(tableName: tableName)
        guard FileManager.default.fileExists(atPath: tableURL.path) else {
            print("ERROR: Table not found:", tableName)
            print("Looked for:", tableURL.path)
            return ""
        }

        let inputWide = trimmed.unicodeScalars.map { UInt32($0) }
        var inputLength = Int32(inputWide.count)

        var outputLength = Int32(max(64, trimmed.count * 8))
        var outputWide = [UInt32](repeating: 0, count: Int(outputLength))

        var ok: Int32 = 0

        inputWide.withUnsafeBufferPointer { inputPtr in
            outputWide.withUnsafeMutableBufferPointer { outputPtr in
                switch mode {
                case .forward:
                    ok = lou_translateString(
                        tableURL.path,
                        inputPtr.baseAddress,
                        &inputLength,
                        outputPtr.baseAddress,
                        &outputLength,
                        nil, nil, 0
                    )

                case .backward:
                    ok = lou_backTranslateString(
                        tableURL.path,
                        inputPtr.baseAddress,
                        &inputLength,
                        outputPtr.baseAddress,
                        &outputLength,
                        nil, nil, 0
                    )
                }
            }
        }

        if ok == 0 {
            print("ERROR: liblouis failed. mode:", mode == .forward ? "forward" : "backward", "table:", tableName)
            return ""
        }

        let units = outputWide.prefix(Int(outputLength)).map { UInt16(truncatingIfNeeded: $0) }
        return String(utf16CodeUnits: units, count: units.count)
    }

    private func resolveTableURL(tableName: String) -> URL {
        // Supports "en-ueb-g2.ctb" and also "en/en-ueb-g2.ctb" if you later add subfolders.
        tablesDir.appendingPathComponent(tableName)
    }
}
