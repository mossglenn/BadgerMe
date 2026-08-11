//
//  OnboardingView.swift
//  BadgerMe — first-launch permission onboarding (§17): explain the app, then request notification
//  and AlarmKit auth WITH rationale (not fire-and-forget). Denied degrades gracefully — the user
//  can proceed and fix permissions later in Settings. No Critical Alerts (L12).
//

import SwiftUI
import AlarmKit
import BadgerKit

struct OnboardingView: View {
    let permissions: Permissions
    let onComplete: (_ startCreating: Bool) -> Void

    @State private var step = 0   // 0 = welcome, 1 = notifications, 2 = alarms

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            switch step {
            case 0:  welcome
            case 1:  notificationsStep
            case 2:  alarmsStep
            default: readyStep
            }
            Spacer()
        }
        .padding(Space.xl)
        .task {
            #if DEBUG
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-uiOnboardStep"), i + 1 < a.count, let n = Int(a[i + 1]) { step = n }
            #endif
            await permissions.refresh()
        }
    }

    private var welcome: some View {
        VStack(spacing: Space.md) {
            Image("badgerhalf")
                .resizable().scaledToFit().frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text("BadgerMe").font(.largeTitle.bold())
            Text("I'm here to annoy you — relentlessly, and for your own good. Most reminders buzz once and politely get out of your way. Not me. I start with a polite notification, but ignore that and I dig in — louder and harder to wave off each time. I don't stop until you mark the task done.")
                .font(.badgerVoice(.body))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            
            Image("badgerpaw.fill").font(.system(size: 56)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Button("Get started") { step = 1 }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var notificationsStep: some View {
        permissionStep(
            icon: "bell.fill", title: "Notifications",
            rationale: "Notifications are how I reach you at first — a tap on the shoulder, easy enough to brush off. Give me permission to use them so I can start pestering you. Politely. For now.",
            allowed: permissions.notifications.isAllowed,
            primaryTitle: "Allow Notifications",
            request: { await permissions.requestNotifications() },
            advance: { step = 2 })
    }

    private var alarmsStep: some View {
        permissionStep(
            icon: "alarm.fill", title: "Alarms",
            rationale: "When a tap on the shoulder stops working, I reach for alarms — loud, persistent, and able to cut through silent mode and Focus, the very settings you'd use to duck me. Give me permission so I can really badger you. Only when you make me.",
            allowed: permissions.alarms == .authorized,
            primaryTitle: "Allow Alarms",
            request: { _ = await permissions.requestAlarms() },
            advance: { step = 3 })
    }

    private var readyStep: some View {
        VStack(spacing: Space.md) {
            Image("badgerpaw.fill").font(.system(size: 48)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Ready to go").font(.title.bold())
            VStack(alignment: .leading, spacing: Space.sm) {
                conceptRow("target", "Give me one thing you really need to do.")
                conceptRow("chart.line.uptrend.xyaxis", "I'll keep getting louder until you mark it done.")
                conceptRow("moon.zzz.fill", "Snooze me too often and I'll take it as encouragement.")
            }
            .font(.badgerVoice(.callout))
            .foregroundStyle(.secondary)
            Button("Create your first Badger") { onComplete(true) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("I'll procrastinate for a bit") { onComplete(false) }.font(.footnote)
        }
    }

    private func conceptRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: Space.lg)
                .accessibilityHidden(true)
            Text(text)
        }
    }

    @ViewBuilder
    private func permissionStep(icon: String, title: String, rationale: String, allowed: Bool,
                                primaryTitle: String, request: @escaping () async -> Void,
                                advance: @escaping () -> Void) -> some View {
        VStack(spacing: Space.md) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title.bold())
            Text(rationale).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if allowed {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(DesignTokens.positive)
                Button("Continue", action: advance)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button(primaryTitle) { Task { await request(); advance() } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Not now", action: advance).font(.footnote)
            }
        }
    }
}
