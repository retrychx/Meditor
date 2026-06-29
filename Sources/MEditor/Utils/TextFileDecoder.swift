import Foundation

enum TextFileDecoder {
    private static let candidateEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .utf32,
        .utf32LittleEndian,
        .utf32BigEndian
    ]

    static func decode(contentsOf url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if let decoded = decode(data) {
            return decoded
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    static func decode(_ data: Data) -> String? {
        for encoding in candidateEncodings {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }
        return nil
    }
}
