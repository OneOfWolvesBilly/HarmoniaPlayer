//
//  ExtendedAttributeService.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Read, write, and clear the com.apple.metadata:kMDItemWhereFroms
//  extended attribute using Darwin xattr APIs.
//
//  DESIGN NOTES
//  ------------
//  - The attribute value is a plist-encoded NSArray<NSString>.
//  - No App Store Sandbox — direct xattr access is permitted.
//  - This service has no dependency on HarmoniaCore.
//  - Errors are exposed only through writeWhereFroms / clearWhereFroms;
//    reads fail silently and return an empty array.
//

import Foundation

/// Errors thrown by ExtendedAttributeService write/clear operations.
enum ExtendedAttributeError: Error, LocalizedError {
    case plistSerializationFailed(Error)
    case writeFailed(Int32)
    case removeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .plistSerializationFailed(let e):
            return "Failed to serialize plist: \(e.localizedDescription)"
        case .writeFailed(let code):
            return "setxattr failed with errno \(code)"
        case .removeFailed(let code):
            return "removexattr failed with errno \(code)"
        }
    }
}

/// Service for reading and writing the kMDItemWhereFroms extended attribute.
///
/// Marked `nonisolated` because this service is a pure Darwin xattr syscall
/// wrapper (`getxattr` / `setxattr` / `removexattr`) with no UI state and no
/// shared mutable state. Under Default Actor Isolation = MainActor it would
/// otherwise be inferred as `@MainActor`, which would incorrectly prevent
/// background use and break `nonisolated` adapters such as
/// `DarwinFileOriginAdapter` that need to call `ExtendedAttributeService()`
/// from a nonisolated context.
///
/// Usage:
/// ```swift
/// let svc = ExtendedAttributeService()
/// let sources = svc.readWhereFroms(url: fileURL)
/// try svc.writeWhereFroms(["https://example.com"], url: fileURL)
/// try svc.clearWhereFroms(url: fileURL)
/// ```
nonisolated struct ExtendedAttributeService {

    // MARK: - Constants

    static let whereFromsKey = "com.apple.metadata:kMDItemWhereFroms"

    // MARK: - Public API

    /// Returns the array of source URL strings stored in kMDItemWhereFroms,
    /// or an empty array if the attribute is absent or cannot be decoded.
    func readWhereFroms(url: URL) -> [String] {
        let key = Self.whereFromsKey
        let path = url.path

        // Query the size of the attribute data
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else { return [] }

        // Read the raw bytes
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, key, &buffer, size, 0, 0)
        guard read == size else { return [] }

        // Decode as plist NSArray<NSString>
        let data = Data(buffer)
        guard
            let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ),
            let array = object as? [String]
        else { return [] }

        return array
    }

    /// Encodes `sources` as a plist and stores it in the kMDItemWhereFroms attribute.
    ///
    /// - Throws: `ExtendedAttributeError.plistSerializationFailed` if encoding fails.
    /// - Throws: `ExtendedAttributeError.writeFailed` if the kernel call fails.
    func writeWhereFroms(_ sources: [String], url: URL) throws {
        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: sources,
                format: .binary,
                options: 0
            )
        } catch {
            throw ExtendedAttributeError.plistSerializationFailed(error)
        }

        let result = data.withUnsafeBytes { bytes in
            setxattr(url.path, Self.whereFromsKey, bytes.baseAddress, data.count, 0, 0)
        }
        if result != 0 {
            throw ExtendedAttributeError.writeFailed(errno)
        }
    }

    /// Removes the kMDItemWhereFroms attribute.
    ///
    /// If the attribute does not exist (ENOATTR / ENODATA), the call is
    /// treated as a no-op — no error is thrown.
    ///
    /// - Throws: `ExtendedAttributeError.removeFailed` for any other kernel error.
    func clearWhereFroms(url: URL) throws {
        let result = removexattr(url.path, Self.whereFromsKey, 0)
        if result != 0 {
            let err = errno
            // ENOATTR (93 on macOS) — attribute does not exist, treat as no-op
            // ENODATA (96) — same semantic on some kernels
            if err == ENOATTR { return }
            throw ExtendedAttributeError.removeFailed(err)
        }
    }
}
