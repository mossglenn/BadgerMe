//
//  ActiveBadgersSnippet.swift
//  BadgerKit — the "what's badgering me" interactive snippet card (M5 CP4b, §11).
//
//  Option A (SDK-verified against the 26.5 AppIntents .swiftinterface): a perform() returns
//  EITHER a typed value OR an interactive snippet, never both — the four `result(…snippetIntent:)`
//  factories are all `Value == Never`. So `GetActiveBadgersIntent` returns `dialog + snippetIntent`
//  (dropping its unused `[BadgerEntity]` value) and points at this SnippetIntent, which renders the
//  card. The card's Done/Snooze buttons use thin, non-discoverable WRAPPER intents that dispatch to
//  the shared engine and then call `ActiveBadgersSnippetIntent.reload()` — so the card refreshes in
//  place (a Done'd Badger drops off; a snoozed one flips to "Snoozed") without coupling the shared
//  MarkBadgerDone/Snooze intents (used by the ambient card + Siri) to this surface.
//
//  #if os(iOS): AppIntents + SwiftUI are iOS-only here; BadgerKit keeps compiling on macOS for
//  `swift test` (the read path this projects from — engine.activeSnapshots() — is tested there).
//

import Foundation

#if os(iOS)
import AppIntents
import SwiftUI

@available(iOS 26.0, *)
public struct ActiveBadgersSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "Active Badgers Card"
    public static var isDiscoverable: Bool { false }   // snippet content only; not a Shortcuts action

    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        let badgers = await engine.activeSnapshots()
        return .result(view: ActiveBadgersSnippetView(badgers: badgers))
    }
}

// MARK: - The card

@available(iOS 26.0, *)
struct ActiveBadgersSnippetView: View {
    let badgers: [BadgerSnapshot]

    var body: some View {
        if badgers.isEmpty {
            Label("Nothing is badgering you", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(badgers) { badger in
                    ActiveBadgerRow(badger: badger)
                    if badger.id != badgers.last?.id { Divider() }
                }
            }
            .padding()
        }
    }
}

@available(iOS 26.0, *)
private struct ActiveBadgerRow: View {
    let badger: BadgerSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: badger.iconName ?? "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(badger.title).font(.headline).lineLimit(1)
                Text(badger.statusSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(intent: SnippetSnoozeBadgerIntent(badgerID: badger.id)) {
                Image(systemName: "moon.zzz")
            }
            .tint(.orange)
            .accessibilityLabel("Snooze \(badger.title)")
            Button(intent: SnippetMarkBadgerDoneIntent(badgerID: badger.id)) {
                Image(systemName: "checkmark")
            }
            .tint(.green)
            .accessibilityLabel("Mark \(badger.title) done")
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Card-scoped wrapper intents
//
// These back the card's buttons only: dispatch to the shared engine, then reload the card so
// the resolved/snoozed Badger updates in place. Kept separate from the shared MarkBadgerDone/
// Snooze intents (ambient card + Siri) so those carry no snippet-reload coupling. Non-discoverable
// so they never surface as standalone Shortcuts actions. LiveActivityIntent → run in the app
// process where the engine @Dependency is registered (L11).

@available(iOS 26.0, *)
public struct SnippetMarkBadgerDoneIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Mark Badger Done (Card)"
    public static var isDiscoverable: Bool { false }

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Dependency public var engine: BadgerEngine

    public init() {}
    public init(badgerID: UUID) { self.badger = BadgerEntity(id: badgerID) }

    public func perform() async throws -> some IntentResult {
        await engine.markDone(badger.id)
        ActiveBadgersSnippetIntent.reload()
        return .result()
    }
}

@available(iOS 26.0, *)
public struct SnippetSnoozeBadgerIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Snooze Badger (Card)"
    public static var isDiscoverable: Bool { false }

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Dependency public var engine: BadgerEngine

    public init() {}
    public init(badgerID: UUID) { self.badger = BadgerEntity(id: badgerID) }

    public func perform() async throws -> some IntentResult {
        await engine.snooze(badger.id, duration: BadgerConfig.defaultSnoozeDuration)
        ActiveBadgersSnippetIntent.reload()
        return .result()
    }
}
#endif
