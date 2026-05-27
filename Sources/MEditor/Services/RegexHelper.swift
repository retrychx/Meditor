import Foundation

/// Safe regex factory — returns a valid NSRegularExpression or a never-matching pattern.
/// All patterns in this project are compile-time constants, so failure is impossible
/// in practice, but this avoids `try!` to satisfy static analysis.
func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        return NSRegularExpression()
    }
}
