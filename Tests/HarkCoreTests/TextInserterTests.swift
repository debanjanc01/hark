import Testing
@testable import HarkCore

struct TextInserterTests {
    @Test(arguments: [
        (nil, "Hello.", ""),          // empty field or caret unknown
        ("." as Character?, "World.", " "),  // dictating twice in a row
        ("o", "world", " "),
        (" ", "World", ""),           // already spaced
        ("\n", "World", ""),
        ("(", "aside", ""),           // opening bracket
        ("/", "tmp", ""),
        ("@", "priya", ""),
        ("o", ", and then", ""),      // punctuation attaches to the previous word
        ("o", ".", ""),
    ])
    func leadingSpace(previous: Character?, text: String, expected: String) {
        #expect(TextInserter.leadingSpace(after: previous, for: text) == expected)
    }
}
