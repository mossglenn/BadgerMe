//
//  BadgerDetailView.swift
//  BadgerMe — the per-Badger detail + history timeline (§16, M7 CP3). Reads the event log via
//  @Query (the L2 payoff); every action dispatches through the engine (L3). Destructive actions
//  confirm (§16).
//

import SwiftUI
import SwiftData
import BadgerKit

struct BadgerDetailView: View {
    let badger: Badger
    let engine: BadgerEngine

    @Environment(\.dismiss) private var dismiss
    @Query private var events: [EventRecord]
    @State private var confirmingStop = false
    @State private var confirmingDelete = false
    var heroNamespace: Namespace.ID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(badger: Badger, engine: BadgerEngine, heroNamespace: Namespace.ID? = nil) {
        self.badger = badger
        self.engine = engine
        self.heroNamespace = heroNamespace
        let id = badger.id
        _events = Query(filter: #Predicate<EventRecord> { $0.badgerID == id },
                        sort: \.sequence, order: .reverse)
    }

    var body: some View {
        // Gate the whole screen on a live model: after Delete the badger detaches, and any stray
        // re-render must touch NO stored/relationship property (title/notes/focusTags/ladder) or
        // SwiftData faults ("backing data detached… without resolving attribute faults"). Rendering
        // nothing here supersedes per-property guards for this view.
        if badger.isLive {
            if let ns = heroNamespace {
                content.navigationTransition(.zoom(sourceID: badger.id, in: ns))
            } else {
                content
            }
        } else {
            Color.clear
        }
    }

    private var content: some View {
        List {
            Section { header }
            Section { actions }
            Section {
                NavigationLink {
                    FocusTagsView(badger: badger, engine: engine)
                } label: {
                    HStack {
                        Label("Focus tags", systemImage: "tag")
                        Spacer()
                        Text(badger.focusTags.isEmpty ? "None" : badger.focusTags.joined(separator: ", "))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Section("History") {
                if events.isEmpty {
                    Text("No events yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(events) { TimelineRow(event: $0) }
                }
            }
        }
        .navigationTitle(badger.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Stop badgering \(badger.title)?", isPresented: $confirmingStop,
                            titleVisibility: .visible) {
            Button("Stop", role: .destructive) { Haptics.impact(.heavy); Task { await engine.stop(badger.id) } }
        } message: { Text("Escalation stops; the Badger is kept in your history.") }
        .confirmationDialog("Delete \(badger.title)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Haptics.impact(.heavy)
                let id = badger.id       // capture before the model detaches
                dismiss()                // pop the detail view first, then delete
                Task { await engine.delete(id) }
            }
        } message: { Text("This removes the Badger and its history for good.") }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            badger.identityImage
                .font(.title2)
                .foregroundStyle(badger.escalationColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(badger.statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(badger.escalationColor)
                if let notes = badger.notes, !notes.isEmpty {
                    Text(notes).font(.body).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Space.xxs)
        .animation(reduceMotion ? nil : Motion.standard, value: badger.escalationTone)
    }

    @ViewBuilder private var actions: some View {
        if !badger.isTerminal {
            Button { Haptics.success(); Task { await engine.markDone(badger.id) } } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            if badger.state != .snoozed {
                Menu {
                    ForEach(BadgerConfig.snoozeOptionsMinutes, id: \.self) { mins in
                        Button("\(mins) min") {
                            Haptics.impact(.light)
                            Task { await engine.snooze(badger.id, duration: TimeInterval(mins * 60)) }
                        }
                    }
                } label: {
                    Label("Snooze…", systemImage: "moon.zzz.fill")
                }
            }
            Button(role: .destructive) { confirmingStop = true } label: {
                Label("Stop", systemImage: "stop.circle.fill")
            }
        } else {
            Button { Haptics.impact(.medium); Task { _ = await engine.replace(badger.id) } } label: {
                Label("Run again", systemImage: "arrow.clockwise.circle.fill")
            }
        }
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private struct TimelineRow: View {
    let event: EventRecord

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .leading)
            Text(ConsoleFormat.humanize(event.kindRaw)
                    + (event.level.map { " (level \($0 + 1))" } ?? ""))
                .font(.callout)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
