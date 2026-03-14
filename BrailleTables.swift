import Foundation

// MARK: - Model

struct BrailleTableMeta: Identifiable, Hashable {
    let id = UUID()

    /// Filename inside the bundled `tables/` directory, example: "en-ueb-g2.ctb"
    let file: String

    /// Full file URL inside the app bundle.
    let url: URL

    /// Parsed metadata (best effort, may be empty depending on table).
    let displayName: String
    let indexName: String
    let languageCode: String
    let type: String
    let grade: String
    let contraction: String
    let dots: String
    let direction: String
    let system: String
    let region: String
    let script: String
    let version: String

    var isLiterary: Bool { type.lowercased() == "literary" }

    /// Good default label for pickers.
    var pickerLabel: String {
        if !grade.isEmpty {
            return "\(displayName) (grade \(grade))"
        }
        return displayName.isEmpty ? file : displayName
    }
}

struct BrailleLanguage: Identifiable, Hashable {
    let id = UUID()
    let code: String        // "en", "af", "zu", etc
    let name: String        // derived from table metadata, best effort
}

// MARK: - Loader + Parser

enum BrailleTables {

    // Cache so we do not re-scan on every UI redraw.
    private static var cachedTables: [BrailleTableMeta]?
    private static var cachedLanguages: [BrailleLanguage]?

    /// Public: returns all parsed tables.
    static func allTables() -> [BrailleTableMeta] {
        if let cachedTables { return cachedTables }
        let tables = scanBundledTablesDirectory()
        cachedTables = tables
        return tables
    }

    /// Public: returns languages derived from the tables.
    static func languages(onlyLiterary: Bool = true) -> [BrailleLanguage] {
        if let cachedLanguages, onlyLiterary == true {
            // The cachedLanguages is built from literary by default below.
            return cachedLanguages
        }

        let tables = allTables()
        let filtered = onlyLiterary ? tables.filter { $0.isLiterary } : tables

        let grouped = Dictionary(grouping: filtered, by: { $0.languageCode })

        let langs: [BrailleLanguage] = grouped
            .map { (code, tables) in
                let name = bestLanguageName(for: code, tables: tables)
                return BrailleLanguage(code: code, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if onlyLiterary {
            cachedLanguages = langs
        }
        return langs
    }

    /// Public: tables for a given language code, optionally filtered.
    static func tables(forLanguage code: String, onlyLiterary: Bool = true) -> [BrailleTableMeta] {
        let tables = allTables().filter { $0.languageCode == code }
        let filtered = onlyLiterary ? tables.filter { $0.isLiterary } : tables

        return filtered.sorted { lhs, rhs in
            // Prefer grade ordering if both have grades, else alphabetical.
            if !lhs.grade.isEmpty, !rhs.grade.isEmpty {
                let l = Double(lhs.grade) ?? 999
                let r = Double(rhs.grade) ?? 999
                if l != r { return l < r }
            }
            let lName = lhs.displayName.isEmpty ? lhs.file : lhs.displayName
            let rName = rhs.displayName.isEmpty ? rhs.file : rhs.displayName
            return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
        }
    }

    /// Public: get available grades for a language (example returns ["1","2","1.5"]).
    static func grades(forLanguage code: String, onlyLiterary: Bool = true) -> [String] {
        let grades = tables(forLanguage: code, onlyLiterary: onlyLiterary)
            .map { $0.grade }
            .filter { !$0.isEmpty }

        // Stable numeric-ish sort
        let unique = Array(Set(grades))
        return unique.sorted {
            (Double($0) ?? 999) < (Double($1) ?? 999)
        }
    }

    /// Public: find the best match for (language + grade) if you want grade pickers.
    static func bestTable(languageCode: String, grade: String, onlyLiterary: Bool = true) -> BrailleTableMeta? {
        let tables = tables(forLanguage: languageCode, onlyLiterary: onlyLiterary)
        if let exact = tables.first(where: { $0.grade == grade }) {
            return exact
        }
        // Fallback: if grade metadata is missing, try filename contains "g\(grade)".
        let needle = "g\(grade)"
        return tables.first(where: { $0.file.lowercased().contains(needle.lowercased()) })
    }

    // MARK: - Internals

    /// Scan `tables/` inside the app bundle and parse metadata from each file header.
    private static func scanBundledTablesDirectory() -> [BrailleTableMeta] {
        guard let tablesDir = Bundle.main.url(forResource: "tables", withExtension: nil) else {
            print("ERROR: tables folder not found in app bundle resources")
            return []
        }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]

        guard let urls = try? fm.contentsOfDirectory(
            at: tablesDir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            print("ERROR: Could not list tables directory")
            return []
        }

        // Keep only table-like files. You can widen this later.
        let candidates = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "ctb" || ext == "utb" || ext == "cti" || ext == "uti"
        }

        var out: [BrailleTableMeta] = []
        out.reserveCapacity(candidates.count)

        for url in candidates {
            let file = url.lastPathComponent
            if let meta = parseMetadata(from: url, file: file) {
                out.append(meta)
            } else {
                // Still include it, but with minimal info, so you can pick it manually if needed.
                out.append(
                    BrailleTableMeta(
                        file: file,
                        url: url,
                        displayName: file,
                        indexName: "",
                        languageCode: "und",
                        type: "",
                        grade: "",
                        contraction: "",
                        dots: "",
                        direction: "",
                        system: "",
                        region: "",
                        script: "",
                        version: ""
                    )
                )
            }
        }

        return out
    }

    /// Parse the first chunk of the file for `#+key:` and `#-key:` lines.
    /// Returns nil if it cannot read the file at all.
    private static func parseMetadata(from url: URL, file: String) -> BrailleTableMeta? {
        // Read a small chunk, metadata is at the top.
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Decode best-effort.
        let text = String(decoding: data.prefix(16_384), as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).prefix(200)

        // Keys we care about
        var displayName = ""
        var indexName = ""
        var language = ""
        var type = ""
        var grade = ""
        var contraction = ""
        var dots = ""
        var direction = ""
        var system = ""
        var region = ""
        var script = ""
        var version = ""

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // Only parse comment metadata lines.
            guard line.hasPrefix("#+") || line.hasPrefix("#-") else { continue }

            // Expected: "#+language: en" or "#-display-name: Unified English ..."
            // Allow extra spaces.
            let prefix = line.prefix(2) // "#+" or "#-"
            let rest = line.dropFirst(2).trimmingCharacters(in: .whitespaces)

            guard let colon = rest.firstIndex(of: ":") else { continue }

            let key = rest[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let val = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            // Normalize a few common keys.
            if prefix == "#-" {
                if key == "display-name" { displayName = String(val) }
                if key == "index-name" { indexName = String(val) }
                if key == "name", displayName.isEmpty { displayName = String(val) }
            } else { // "#+"
                if key == "language" { language = String(val) }
                if key == "type" { type = String(val) }
                if key == "grade" { grade = String(val) }
                if key == "contraction" { contraction = String(val) }
                if key == "dots" { dots = String(val) }
                if key == "direction" { direction = String(val) }
                if key == "system" { system = String(val) }
                if key == "region" { region = String(val) }
                if key == "script" { script = String(val) }
                if key == "version" { version = String(val) }
            }
        }

        // Basic cleanup
        if displayName.isEmpty { displayName = file }
        if language.isEmpty { language = "und" } // undetermined

        return BrailleTableMeta(
            file: file,
            url: url,
            displayName: displayName,
            indexName: indexName,
            languageCode: language,
            type: type,
            grade: grade,
            contraction: contraction,
            dots: dots,
            direction: direction,
            system: system,
            region: region,
            script: script,
            version: version
        )
    }

    private static func bestLanguageName(for code: String, tables: [BrailleTableMeta]) -> String {
        // Prefer indexName first chunk (often "English, ...", "isiZulu, ...")
        let candidates = tables.compactMap { t -> String? in
            if !t.indexName.isEmpty {
                return t.indexName.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
            }
            return nil
        }

        if let mostCommon = mostFrequentString(in: candidates), !mostCommon.isEmpty {
            return mostCommon
        }

        // Next best: derive from displayName
        let displayCandidates = tables.map(\.displayName)
        if let mostCommon = mostFrequentString(in: displayCandidates), !mostCommon.isEmpty {
            return mostCommon
        }

        // Fallback: just show the code.
        return code
    }

    private static func mostFrequentString(in list: [String]) -> String? {
        guard !list.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for s in list {
            let key = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
