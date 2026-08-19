import Foundation
import Testing

/// A unique temporary directory that exists for the duration of a single test.
enum TemporaryDirectory {
    @TaskLocal fileprivate static var current: URL?

    /// The directory created for the running test.
    static var url: URL {
        guard let current else {
            preconditionFailure(
                "TemporaryDirectory.url requires the `.temporaryDirectory` trait on the test or its suite"
            )
        }
        return current
    }
}

/// Creates ``TemporaryDirectory/url`` before a test runs and removes it afterwards.
///
/// Applying it to a suite gives every test in that suite its own directory, so tests
/// that write to disk stay isolated from each other.
struct TemporaryDirectoryTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try await TemporaryDirectory.$current.withValue(directory) {
            try await function()
        }
    }
}

extension Trait where Self == TemporaryDirectoryTrait {
    static var temporaryDirectory: Self { Self() }
}
