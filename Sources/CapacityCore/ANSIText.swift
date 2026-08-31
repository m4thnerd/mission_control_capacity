import Foundation

public enum ANSIText {
    public static func clean(_ input: String) -> String {
        var value = input
        value = value.replacingOccurrences(
            of: #"\u001B\][^\u0007\u001B]*(?:\u0007|\u001B\\)"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\u001B\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\u001B[()][A-Za-z0-9]"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: "\r", with: "\n")

        let allowed = value.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || scalar.value >= 32
        }
        return String(String.UnicodeScalarView(allowed))
    }
}

enum RegexCapture {
    static func first(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
    ) -> [String]? {
        all(pattern, in: text, options: options).first
    }

    static func last(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
    ) -> [String]? {
        all(pattern, in: text, options: options).last
    }

    static func all(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let captureRange = match.range(at: index)
                guard captureRange.location != NSNotFound,
                      let range = Range(captureRange, in: text) else { return "" }
                return String(text[range])
            }
        }
    }
}
