import Foundation

extension Error {
    /// A human-readable message for reporting errors through MCP results.
    ///
    /// `localizedDescription` on a plain Swift error collapses to an opaque
    /// "(Module.Type error N.)" string, discarding messages provided via
    /// `CustomStringConvertible` (e.g. `XCodeProjError`), so prefer
    /// `errorDescription` for `LocalizedError` and fall back to
    /// `String(describing:)` for everything else.
    var descriptiveMessage: String {
        if let localizedError = self as? LocalizedError,
            let description = localizedError.errorDescription
        {
            return description
        }
        return String(describing: self)
    }
}
