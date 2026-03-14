import SwiftUI

struct ContentView: View {

    @State private var inputText: String = ""
    @State private var brailleOutput: String = ""

    // Dynamic options discovered from tables metadata
    @State private var languageOptions: [BrailleLanguage] = []
    @State private var gradeOptions: [String] = []
    @State private var tableOptions: [BrailleTableMeta] = []

    // Current selections
    @State private var selectedLanguageCode: String = "en"
    @State private var selectedGrade: String = "2"
    @State private var selectedTableFile: String = "en-ueb-g2.ctb"

    private let translator = BrailleTranslator()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Anvill Translator")
                .font(.largeTitle)
                .bold()

            HStack(spacing: 16) {

                VStack(alignment: .leading, spacing: 6) {
                    Text("Language")
                        .font(.headline)

                    Picker("Language", selection: $selectedLanguageCode) {
                        ForEach(languageOptions) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Language")
                    .onChange(of: selectedLanguageCode) { _ in
                        refreshGradeAndTableOptions()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Braille Grade")
                        .font(.headline)

                    Picker("Braille Grade", selection: $selectedGrade) {
                        ForEach(gradeOptions, id: \.self) { g in
                            Text("Grade \(g)").tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Braille Grade")
                    .onChange(of: selectedGrade) { _ in
                        pickBestTableForCurrentSelection()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Table")
                        .font(.headline)

                    Picker("Table", selection: $selectedTableFile) {
                        ForEach(tableOptions, id: \.file) { t in
                            Text(t.pickerLabel).tag(t.file)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Table")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Plain text")
                    .font(.headline)

                TextField("Enter text to translate", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        runTranslation()
                    }
            }

            HStack(spacing: 12) {
                Button("Translate") {
                    runTranslation()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Clear") {
                    inputText = ""
                    brailleOutput = ""
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Braille output")
                    .font(.headline)

                TextEditor(text: $brailleOutput)
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                    .accessibilityLabel("Braille output")
            }

            Spacer(minLength: 0)
        }
        .padding()
        .onAppear {
            bootstrapTables()
        }
    }

    private func bootstrapTables() {
        // Default to literary tables only, because that is what you are building for first.
        languageOptions = BrailleTables.languages(onlyLiterary: true)

        // Pick a sensible default language, prefer English if present.
        if languageOptions.contains(where: { $0.code == "en" }) {
            selectedLanguageCode = "en"
        } else if let first = languageOptions.first {
            selectedLanguageCode = first.code
        }

        refreshGradeAndTableOptions()

        // Prefer grade 2 if available, else first available grade.
        if gradeOptions.contains("2") {
            selectedGrade = "2"
        } else if let firstGrade = gradeOptions.first {
            selectedGrade = firstGrade
        }

        pickBestTableForCurrentSelection()
    }

    private func refreshGradeAndTableOptions() {
        gradeOptions = BrailleTables.grades(forLanguage: selectedLanguageCode, onlyLiterary: true)

        // If no grade metadata exists for a language, we still allow table selection.
        // In that case we show a single "All" grade slot, and the user picks a table directly.
        if gradeOptions.isEmpty {
            gradeOptions = ["All"]
            selectedGrade = "All"
        } else {
            if !gradeOptions.contains(selectedGrade) {
                selectedGrade = gradeOptions.contains("2") ? "2" : (gradeOptions.first ?? "1")
            }
        }

        // Populate table picker for this language.
        tableOptions = BrailleTables.tables(forLanguage: selectedLanguageCode, onlyLiterary: true)

        // If we have grade metadata, filter tables for that grade first.
        if selectedGrade != "All" {
            let gradeFiltered = tableOptions.filter { $0.grade == selectedGrade }
            if !gradeFiltered.isEmpty {
                tableOptions = gradeFiltered
            }
        }

        // Ensure selected table is valid.
        if !tableOptions.contains(where: { $0.file == selectedTableFile }) {
            selectedTableFile = tableOptions.first?.file ?? selectedTableFile
        }
    }

    private func pickBestTableForCurrentSelection() {
        if selectedGrade == "All" {
            selectedTableFile = tableOptions.first?.file ?? selectedTableFile
            return
        }

        if let best = BrailleTables.bestTable(languageCode: selectedLanguageCode, grade: selectedGrade, onlyLiterary: true) {
            selectedTableFile = best.file
            // Also refresh the tableOptions so the table picker matches the grade-filter logic
            refreshGradeAndTableOptions()
            return
        }

        // Fallback: just pick first table in this language
        selectedTableFile = tableOptions.first?.file ?? selectedTableFile
    }

    private func runTranslation() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            brailleOutput = ""
            return
        }

        // Translate using the selected table file name from metadata scanning.
        brailleOutput = translator.translate(text: trimmed, tableName: selectedTableFile)
    }
}

#Preview {
    ContentView()
}
