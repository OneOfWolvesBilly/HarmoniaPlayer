//
//  DarwinFileOriginAdapter.swift
//  HarmoniaPlayer / Shared / Services
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Concrete `FileOriginService` backed by `ExtendedAttributeService`.
//  Translates low-level Darwin xattr errors into `FileOriginError` payloads
//  the UI layer can display without knowing about errno.
//
//  DESIGN NOTES
//  ------------
//  - `ExtendedAttributeService` remains a bottom-level Darwin utility;
//    this adapter is the single Application-Layer entry point to it.
//  - The adapter holds the utility internally rather than injecting it,
//    because `ExtendedAttributeService` is a value-type Darwin wrapper
//    with no protocol and no test seam — all tests exercise the real
//    xattr calls against temporary files.
//  - `read(url:)` does not throw. On any failure it returns `[]`, matching
//    the behaviour callers rely on (absent metadata == empty list).
//  - The class is marked `nonisolated` so both its initializer and its
//    conformance to `FileOriginService` stay nonisolated under Swift 6
//    strict concurrency, even when instantiated from `@MainActor`-isolated
//    contexts such as `XCTestCase`. Without `nonisolated`, Swift 6 would
//    infer the conformance as MainActor-bound and reject its use through
//    the nonisolated `FileOriginService` protocol.
//    Reference: Donny Wals — "Solving actor-isolated protocol conformance
//    related errors in Swift 6.2"
//

import Foundation

/// Darwin-backed `FileOriginService` using the kMDItemWhereFroms xattr.
nonisolated final class DarwinFileOriginAdapter: FileOriginService {

    // MARK: - Dependencies

    private let xattrService = ExtendedAttributeService()

    // MARK: - Initialization

    init() {}

    // MARK: - FileOriginService

    func read(url: URL) -> [String] {
        xattrService.readWhereFroms(url: url)
    }

    func write(_ sources: [String], url: URL) throws {
        do {
            try xattrService.writeWhereFroms(sources, url: url)
        } catch let error as ExtendedAttributeError {
            throw FileOriginError.writeFailed(
                error.errorDescription ?? "Unknown write failure"
            )
        }
    }

    func clear(url: URL) throws {
        do {
            try xattrService.clearWhereFroms(url: url)
        } catch let error as ExtendedAttributeError {
            throw FileOriginError.clearFailed(
                error.errorDescription ?? "Unknown clear failure"
            )
        }
    }
}
