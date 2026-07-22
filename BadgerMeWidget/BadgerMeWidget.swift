//
//  BadgerMeWidget.swift
//  BadgerMeWidget — home/lock-screen glance of what's badgering the user (§11, M6 CP3).
//
//  A StaticConfiguration widget (small + medium). Its TimelineProvider reads the shared
//  App-Group store via BadgerKit's read-only BadgerWidgetReader (no engine in the widget
//  process) and shows the active count + the most-urgent Badger with a fixed-target
//  countdown and an inline Done (MarkBadgerDoneIntent runs in-app, headless). Refreshes when
//  the soonest escalation passes so the count/most-urgent stay current.
//

import WidgetKit
import SwiftUI
import AppIntents
import BadgerKit

struct BadgerWidgetEntry: TimelineEntry {
    let date: Date
    let summary: BadgerWidgetSummary
}

struct BadgerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BadgerWidgetEntry {
        BadgerWidgetEntry(date: Date(), summary: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (BadgerWidgetEntry) -> Void) {
        completion(BadgerWidgetEntry(date: Date(), summary: BadgerWidgetReader.summary()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BadgerWidgetEntry>) -> Void) {
        let now = Date()
        let summary = BadgerWidgetReader.summary(now: now)
        let entry = BadgerWidgetEntry(date: now, summary: summary)
        // Refresh when the soonest escalation passes (count/most-urgent may change), else 15m.
        let refresh = summary.mostUrgent.map { max($0.nextFire, now.addingTimeInterval(60)) }
            ?? now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct BadgerWidgetView: View {
    let entry: BadgerWidgetEntry

    var body: some View {
        if let urgent = entry.summary.mostUrgent {
            active(urgent, count: entry.summary.activeCount)
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(DesignTokens.positive)
            Text("All clear").font(.headline)
            Text("Nothing badgering you").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func active(_ urgent: BadgerWidgetSummary.Item, count: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: urgent.iconName ?? "pawprint.fill")
                    .foregroundStyle(urgent.tone.color())
                Text(urgent.title).font(.headline).lineLimit(1)
            }
            countdown(to: urgent.nextFire).font(.title2).monospacedDigit()
                .foregroundStyle(urgent.tone.color())
            if count > 1 {
                Text("+\(count - 1) more badgering").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(intent: MarkBadgerDoneIntent(badgerID: urgent.id)) {
                Label("Done", systemImage: "checkmark").font(.caption).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.positive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func countdown(to fire: Date) -> some View {
        if fire > entry.date {
            Text(timerInterval: entry.date...fire, countsDown: true)
        } else {
            Text("now")
        }
    }
}

struct BadgerMeWidget: Widget {
    let kind = "BadgerMeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BadgerWidgetProvider()) { entry in
            BadgerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Badgering")
        .description("Your most urgent Badger, its countdown, and a Done button.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
