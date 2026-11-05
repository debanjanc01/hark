import Foundation
import Testing
@testable import HarkCore

@MainActor
struct DeveloperWordsTests {
    /// The model's text, with every word at the same confidence.
    private func transcript(_ text: String, probability: Double = 0.5, language: String = "en") -> Transcript {
        Transcript(text: text, language: language, words: text.split(separator: " ").map {
            Transcript.Word(word: String($0), probability: probability)
        })
    }

    private func fixed(_ text: String, probability: Double = 0.5) -> String {
        DeveloperWords.defaults.correct(transcript(text, probability: probability))
    }

    /// What the model really wrote for spoken terms.
    @Test(arguments: [
        ("I ran cube control delete on the namespace.", "I ran kubectl delete on the namespace."),
        ("Use cubes ideal to apply the deployment.", "Use kubectl to apply the deployment."),
        ("Cube Cutton", "kubectl"),
        ("Open Docker Dexter.", "Open Docker Desktop."),
        ("Docker Deckstop.", "Docker Desktop."),
        ("Deploy it to cubanities.", "Deploy it to Kubernetes."),
        ("We start enginex on the server.", "We start nginx on the server."),
        ("Our postgrace database is full.", "Our Postgres database is full."),
        ("validate the Jason schema.", "validate the JSON schema."),
        ("Fix the Yammel Indentation.", "Fix the YAML Indentation."),
        ("Write a sequel query.", "Write a SQL query."),
        ("You need Sudo for that command.", "You need sudo for that command."),
        ("Push in to get up.", "Push in to GitHub."),
        ("Bind the server to local host.", "Bind the server to localhost."),
        ("Run terraform plan.", "Run Terraform plan."),
    ])
    func fixesMisheardTerms(heard: String, expected: String) {
        #expect(fixed(heard) == expected)
    }

    /// Ordinary sentences stay as they are, even if the model doubted every word.
    @Test(arguments: [
        "Jason sent me the file this morning.",
        "The sequel to that movie was better.",
        "We visited a cube city last year.",
        "The cube got in the way.",
        "Our local host family was very kind.",
        "We drank some home brew last night.",
        "Attach the email file to the invoice",
        "My email is in the config file",
        "Sit down and run the command",
        "Rugs and string are in the garage",
        "Rocks are heavy",
        "Screenshots are on my desktop",
        "The pod of whales swam past the boat",
        "Open the doctor's note",
    ])
    func leavesOrdinarySpeechAlone(_ text: String) {
        #expect(fixed(text) == text)
    }

    @Test func nothingChangesExactlyAsTranscribed() {
        let text = "Please  call me."
        #expect(DeveloperWords.defaults.correct(Transcript(text: text, language: "en", words: nil)) == text)
    }

    @Test func worksWithoutWordConfidence() {
        let heard = Transcript(text: "Use cubes ideal to apply the deployment.", language: "en", words: nil)
        #expect(DeveloperWords.defaults.correct(heard) == "Use kubectl to apply the deployment.")
    }

    @Test func onlyCorrectsEnglish() {
        let heard = transcript("Use cubes ideal to apply the deployment.", language: "de")
        #expect(DeveloperWords.defaults.correct(heard) == heard.text)
    }

    @Test func customWordsAreNeverReplaced() {
        let heard = transcript("validate the Jason schema.")
        #expect(DeveloperWords.defaults.correct(heard, keeping: ["Jason"]) == heard.text)
    }

    @Test func customWordsSetTheSpelling() {
        let heard = transcript("Run terraform plan.")
        #expect(DeveloperWords.defaults.correct(heard, keeping: ["TERRAFORM"]) == "Run TERRAFORM plan.")
    }

    @Test func addedFormsAreAlwaysReplaced() {
        // Real words the model was sure of: left alone until the person says otherwise.
        let heard = transcript("Cube cattle get pods.", probability: 0.99)
        #expect(DeveloperWords.defaults.correct(heard) == heard.text)
        let edited = DeveloperWords(list: "kubectl: kube control, cube cattle")
        #expect(edited.correct(heard) == "kubectl get pods.")
    }

    @Test func addedTermsWork() {
        let words = DeveloperWords(list: "Tailscale: tail scale, tale scale")
        #expect(words.correct(transcript("Restart tale scale now.")) == "Restart Tailscale now.")
    }

    @Test func removedTermsStayOff() {
        let list = DeveloperWords.defaults.entries.filter { $0.term != "Postgres" }
        let heard = transcript("Our postgrace database is full.")
        #expect(DeveloperWords(entries: list).correct(heard) == heard.text)
    }

    @Test func listSurvivesEditing() {
        #expect(DeveloperWords(list: DeveloperWords.defaults.list) == .defaults)
        let parsed = DeveloperWords(list: "  kubectl :  cube cattle ,, cube control \n\n JSON\n: nothing\n")
        #expect(parsed.entries == [
            .init(term: "kubectl", soundsLike: ["cube cattle", "cube control"]),
            .init(term: "JSON", soundsLike: []),
        ])
    }

    @Test func soundKeysMatchAcrossSpellings() {
        #expect(DeveloperWords.key("cube cuttle") == DeveloperWords.key("kube cuddle"))
        #expect(DeveloperWords.key("CubeCTL") == DeveloperWords.key("kube C T L"))
    }

    @Test func settingsKeepOnlyRealEdits() {
        let suite = "hark-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        #expect(settings.fixesDeveloperWords)
        #expect(settings.developerWords == .defaults)

        settings.developerWordsList = "kubectl: cube cattle"
        #expect(Settings(defaults: defaults).developerWords.entries.map(\.term) == ["kubectl"])

        settings.developerWordsList = DeveloperWords.defaults.list
        #expect(defaults.string(forKey: "developerWords") == nil)
    }
}
