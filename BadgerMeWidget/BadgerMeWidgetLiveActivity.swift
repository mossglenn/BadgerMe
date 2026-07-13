//
//  BadgerMeWidgetLiveActivity.swift
//  BadgerMeWidget
//
//  The ambient per-Badger Live Activity (§12, M5 CP2b): a never-stall summary that counts
//  down to a fixed nextFireDate and flips to an overdue treatment when the system marks it
//  stale (staleDate passed while backgrounded — context.isStale). Distinct from the AlarmKit
//  alarm presentation (BadgerMeWidgetAlarmActivity). Non-interactive for now; Done/Snooze
//  buttons land in CP4.
//

import ActivityKit
import WidgetKit
import SwiftUI
import BadgerKit

struct BadgerMeWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BadgerActivityAttributes.self) { context in
            AmbientLockScreenView(context: context)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: ambientIcon(context))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AmbientCountdown(context: context).font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ambientStatusLine(context)).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: ambientIcon(context))
            } compactTrailing: {
                AmbientCountdown(context: context).monospacedDigit()
            } minimal: {
                Image(systemName: ambientIcon(context))
            }
        }
    }
}

private struct AmbientLockScreenView: View {
    let context: ActivityViewContext<BadgerActivityAttributes>
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ambientIcon(context))
                .font(.title2)
                .foregroundStyle(context.isStale ? .orange : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title).font(.headline).lineLimit(1)
                Text(ambientStatusLine(context)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            AmbientCountdown(context: context).font(.title2.monospacedDigit())
        }
    }
}

private struct AmbientCountdown: View {
    let context: ActivityViewContext<BadgerActivityAttributes>
    var body: some View {
        switch context.state.phase {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .stopped:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        default:
            if let fire = context.state.nextFireDate {
                // min(now, fire)...fire keeps the range valid even if fire is past
                // (Text clamps the display at zero — never runs away counting up). §12.
                Text(timerInterval: min(Date(), fire)...fire, countsDown: true)
            } else {
                Text("—")
            }
        }
    }
}

// MARK: - Presentation helpers

private func ambientIcon(_ context: ActivityViewContext<BadgerActivityAttributes>) -> String {
    if context.isStale, isEscalating(context.state.phase) { return "exclamationmark.triangle.fill" }
    switch context.state.phase {
    case .done:    return "checkmark.circle.fill"
    case .stopped: return "xmark.circle.fill"
    case .snoozed: return "moon.zzz.fill"
    default:       return "bell.badge.fill"
    }
}

private func ambientStatusLine(_ context: ActivityViewContext<BadgerActivityAttributes>) -> String {
    let s = context.state
    if context.isStale, isEscalating(s.phase) { return "Overdue — escalating" }
    switch s.phase {
    case .armed:      return "Armed"
    case .escalating: return "Level \(s.currentLevelIndex + 1) of \(s.totalLevels)"
    case .repeating:  return "Repeating — level \(s.totalLevels) of \(s.totalLevels)"
    case .snoozed:    return "Snoozed"
    case .done:       return "Done"
    case .stopped:    return "Stopped"
    case .overdue:    return "Overdue — escalating"
    }
}

/// Phases where a passed staleDate means "overdue" (vs. terminal / snoozed, which don't).
private func isEscalating(_ phase: BadgerActivityAttributes.Phase) -> Bool {
    switch phase {
    case .armed, .escalating, .repeating, .overdue: return true
    case .snoozed, .done, .stopped:                 return false
    }
}
