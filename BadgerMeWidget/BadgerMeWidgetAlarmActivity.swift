//
//  BadgerMeWidgetAlarmActivity.swift
//  BadgerMeWidget
//
//  CP1 (M5): AlarmKit's alarm-presentation Live Activity. AlarmKit drives each hard rung's
//  alert through a system-managed Live Activity keyed on AlarmAttributes<BadgerAlarmMetadata>;
//  without a widget rendering it the alert surface is fragile — device A5 saw a swipe leave
//  alarm audio sounding with no visible UI. This renders the system-driven presentation state
//  (AlarmPresentationState.mode: .countdown / .paused / .alert). Spec §12, L7.
//

#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
import WidgetKit
import SwiftUI
import BadgerKit

@available(iOS 26.1, *)
struct BadgerAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<BadgerAlarmMetadata>.self) { context in
            AlarmLockScreenView(context: context)
                .activityBackgroundTint(context.attributes.tintColor.opacity(0.12))
                .activitySystemActionForegroundColor(context.attributes.tintColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmModeReadout(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                AlarmModeReadout(context: context)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }
}

/// A compact readout of the current alarm mode: countdown timer, paused, or firing.
@available(iOS 26.1, *)
private struct AlarmModeReadout: View {
    let context: ActivityViewContext<AlarmAttributes<BadgerAlarmMetadata>>
    var body: some View {
        switch context.state.mode {
        case .countdown(let c):
            // Guard the range: in .countdown mode startDate <= fireDate holds, but a clock
            // adjustment or SDK edge must not trap ClosedRange — that would fail the whole
            // alarm presentation (the A5 "audio, no UI" failure class). min(...) keeps it
            // valid; Text clamps the display at zero past fireDate. §12, code review #2.
            Text(timerInterval: min(c.startDate, c.fireDate)...c.fireDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 68)
        case .paused:
            Image(systemName: "pause.fill")
                .foregroundStyle(context.attributes.tintColor)
        case .alert:
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .foregroundStyle(context.attributes.tintColor)
        @unknown default:
            Image(systemName: "alarm.fill")
                .foregroundStyle(context.attributes.tintColor)
        }
    }
}

/// Lock Screen / banner presentation for an armed hard rung.
@available(iOS 26.1, *)
private struct AlarmLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<BadgerAlarmMetadata>>
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.title2)
                .foregroundStyle(context.attributes.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.presentation.alert.title)
                    .font(.headline)
                    .lineLimit(1)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            AlarmModeReadout(context: context)
                .font(.title3)
        }
        .padding()
    }

    @ViewBuilder
    private var subtitle: some View {
        switch context.state.mode {
        case .countdown: Text("Escalating")
        case .paused:    Text("Paused")
        case .alert:     Text("Time to act")
        @unknown default: Text("Badgering")
        }
    }
}
#endif
