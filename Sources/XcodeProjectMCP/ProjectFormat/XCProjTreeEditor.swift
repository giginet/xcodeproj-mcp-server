import Foundation
import XcodeProjectFormat

/// Traversal and rewrite helpers for the `XCSchema` groups-and-files tree.
///
/// `XCSchema` models are value types, so a nested node cannot be mutated in
/// place through a reference like a `PBXGroup` can: every mutation locates the
/// node by index path and rebuilds the spine of the tree. This is the value
/// tree counterpart of `GroupFinder` and the ad-hoc `PBXGroup` recursion inside
/// the tools' pbxproj arms.
enum XCProjTreeEditor {
    // MARK: - Group lookup

    /// The name a group is displayed under: its explicit name, or the last
    /// component of its path.
    static func displayName(of group: XCSchema.Group) -> String {
        if !group.name.isEmpty {
            return group.name
        }
        let path = group.path.stringRepresentation
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Finds a group by flat name/path match anywhere in the tree, or by a
    /// hierarchical "Parent/Child" path from the top level, mirroring
    /// `GroupFinder.findGroup(named:in:)`. Returns the index path into `refs`.
    static func findGroup(named key: String, in refs: [XCSchema.Reference]) -> [Int]? {
        if let indexPath = findGroupFlat(named: key, in: refs) {
            return indexPath
        }
        let components = key.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nil }
        return findGroup(pathComponents: components, in: refs)
    }

    private static func findGroupFlat(named key: String, in refs: [XCSchema.Reference]) -> [Int]? {
        for (index, reference) in refs.enumerated() {
            guard case .group(let group) = reference else { continue }
            if group.name == key || group.path.stringRepresentation == key {
                return [index]
            }
            if let childPath = findGroupFlat(named: key, in: group.children) {
                return [index] + childPath
            }
        }
        return nil
    }

    private static func findGroup(pathComponents: [String], in refs: [XCSchema.Reference]) -> [Int]?
    {
        guard let component = pathComponents.first else { return nil }
        for (index, reference) in refs.enumerated() {
            guard case .group(let group) = reference, displayName(of: group) == component
            else { continue }
            if pathComponents.count == 1 {
                return [index]
            }
            if let childPath = findGroup(
                pathComponents: Array(pathComponents.dropFirst()), in: group.children)
            {
                return [index] + childPath
            }
        }
        return nil
    }

    static func group(at indexPath: [Int], in refs: [XCSchema.Reference]) -> XCSchema.Group? {
        guard let index = indexPath.first, refs.indices.contains(index),
            case .group(let group) = refs[index]
        else { return nil }
        if indexPath.count == 1 {
            return group
        }
        return self.group(at: Array(indexPath.dropFirst()), in: group.children)
    }

    /// The on-disk directory components contributed by the groups along the
    /// index path (each group's own path, when non-empty), relative to the
    /// directory containing the `.xcodeproj`.
    static func directoryComponents(toGroupAt indexPath: [Int], in refs: [XCSchema.Reference])
        -> [String]
    {
        guard let index = indexPath.first, refs.indices.contains(index),
            case .group(let group) = refs[index]
        else { return [] }
        let own = group.path.stringRepresentation
        let components = own.isEmpty ? [] : own.split(separator: "/").map(String.init)
        return components
            + directoryComponents(toGroupAt: Array(indexPath.dropFirst()), in: group.children)
    }

    // MARK: - Group mutation

    /// Mutates the group at the index path, rebuilding the tree spine.
    static func modifyGroup(
        at indexPath: [Int], in refs: inout [XCSchema.Reference],
        _ body: (inout XCSchema.Group) -> Void
    ) {
        guard let index = indexPath.first, refs.indices.contains(index),
            case .group(var group) = refs[index]
        else { return }
        if indexPath.count == 1 {
            body(&group)
        } else {
            modifyGroup(at: Array(indexPath.dropFirst()), in: &group.children, body)
        }
        refs[index] = .group(group)
    }

    /// Appends a reference to the group at the index path, or to the top level
    /// when the index path is nil.
    static func append(
        _ reference: XCSchema.Reference, toGroupAt indexPath: [Int]?,
        in refs: inout [XCSchema.Reference]
    ) {
        guard let indexPath else {
            refs.append(reference)
            return
        }
        modifyGroup(at: indexPath, in: &refs) { group in
            group.children.append(reference)
        }
    }

    // MARK: - File references

    /// Depth-first visit of every file reference in the tree.
    static func forEachFileReference(
        in refs: [XCSchema.Reference], _ body: (XCSchema.FileReference) -> Void
    ) {
        for reference in refs {
            switch reference {
            case .fileReference(let fileReference):
                body(fileReference)
            case .group(let group):
                forEachFileReference(in: group.children, body)
            case .variantGroup(let variantGroup):
                variantGroup.children.forEach(body)
            case .versionGroup(let versionGroup):
                versionGroup.children.forEach(body)
            case .folder:
                continue
            }
        }
    }

    /// Rewrites every file reference in the tree (variant/version group
    /// children included), rebuilding the spine.
    static func mutateFileReferences(
        in refs: inout [XCSchema.Reference], _ body: (inout XCSchema.FileReference) -> Void
    ) {
        for index in refs.indices {
            switch refs[index] {
            case .fileReference(var fileReference):
                body(&fileReference)
                refs[index] = .fileReference(fileReference)
            case .group(var group):
                mutateFileReferences(in: &group.children, body)
                refs[index] = .group(group)
            case .variantGroup(var variantGroup):
                for childIndex in variantGroup.children.indices {
                    body(&variantGroup.children[childIndex])
                }
                refs[index] = .variantGroup(variantGroup)
            case .versionGroup(var versionGroup):
                for childIndex in versionGroup.children.indices {
                    body(&versionGroup.children[childIndex])
                }
                refs[index] = .versionGroup(versionGroup)
            case .folder:
                continue
            }
        }
    }

    /// Rewrites the first file reference matching the predicate. The update
    /// closure receives the directory components of the ancestor groups so it
    /// can compute group-relative paths. Returns true when a match was found.
    @discardableResult
    static func updateFirstFileReference(
        in refs: inout [XCSchema.Reference], groupDirectory: [String] = [],
        where predicate: (XCSchema.FileReference) -> Bool,
        update: (inout XCSchema.FileReference, _ groupDirectory: [String]) -> Void
    ) -> Bool {
        for index in refs.indices {
            switch refs[index] {
            case .fileReference(var fileReference):
                if predicate(fileReference) {
                    update(&fileReference, groupDirectory)
                    refs[index] = .fileReference(fileReference)
                    return true
                }
            case .group(var group):
                let own = group.path.stringRepresentation
                let childDirectory =
                    groupDirectory
                    + (own.isEmpty ? [] : own.split(separator: "/").map(String.init))
                if updateFirstFileReference(
                    in: &group.children, groupDirectory: childDirectory,
                    where: predicate, update: update)
                {
                    refs[index] = .group(group)
                    return true
                }
            case .variantGroup, .versionGroup, .folder:
                continue
            }
        }
        return false
    }

    /// Removes the first file reference matching the predicate and returns it.
    static func removeFirstFileReference(
        in refs: inout [XCSchema.Reference],
        where predicate: (XCSchema.FileReference) -> Bool
    ) -> XCSchema.FileReference? {
        for index in refs.indices {
            switch refs[index] {
            case .fileReference(let fileReference):
                if predicate(fileReference) {
                    refs.remove(at: index)
                    return fileReference
                }
            case .group(var group):
                if let removed = removeFirstFileReference(
                    in: &group.children, where: predicate)
                {
                    refs[index] = .group(group)
                    return removed
                }
            case .variantGroup, .versionGroup, .folder:
                continue
            }
        }
        return nil
    }

    /// Whether any group in the tree carries the given name.
    static func containsGroup(named key: String, in refs: [XCSchema.Reference]) -> Bool {
        for reference in refs {
            guard case .group(let group) = reference else { continue }
            if group.name == key || displayName(of: group) == key {
                return true
            }
            if containsGroup(named: key, in: group.children) {
                return true
            }
        }
        return false
    }
}
