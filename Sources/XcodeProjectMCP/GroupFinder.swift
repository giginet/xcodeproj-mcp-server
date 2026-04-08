import Foundation
import XcodeProj

/// Utility for finding PBXGroup by hierarchical path (e.g. "TopLevel/Nested/DeeplyNested")
/// as returned by ListGroupsTool.
enum GroupFinder {
    /// Find a group by name, path property, or hierarchical path.
    /// Hierarchical paths like "Parent/Child" are resolved by traversing
    /// the group tree from the main group.
    static func findGroup(
        named groupName: String,
        in pbxproj: PBXProj
    ) throws -> PBXGroup {
        // First, try direct match (single-component name or path)
        if let found = pbxproj.groups.first(where: {
            $0.name == groupName || $0.path == groupName
        }) {
            return found
        }

        // If the name contains "/", try hierarchical traversal
        let components = groupName.split(separator: "/").map(String.init)
        if components.count > 1 {
            guard let project = try pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw GroupFinderError.groupNotFound(groupName)
            }

            var currentGroup = mainGroup
            for component in components {
                guard
                    let childGroup = currentGroup.children.compactMap({ $0 as? PBXGroup }).first(
                        where: {
                            $0.name == component || $0.path == component
                        })
                else {
                    throw GroupFinderError.groupNotFound(groupName)
                }
                currentGroup = childGroup
            }
            return currentGroup
        }

        throw GroupFinderError.groupNotFound(groupName)
    }

    enum GroupFinderError: LocalizedError {
        case groupNotFound(String)

        var errorDescription: String? {
            switch self {
            case .groupNotFound(let name):
                return "Group '\(name)' not found in project"
            }
        }
    }
}
