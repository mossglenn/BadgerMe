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
    let onComplete: () -> Void

    @State private var step = 0   // 0 = welcome, 1 = notifications, 2 = alarms

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            switch step {
            case 0:  welcome
            case 1:  notificationsStep
            default: alarmsStep
            }
            Spacer()
        }
        .padding(28)
        .task { await permissions.refresh() }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge.fill").font(.system(size: 56)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("BadgerMe").font(.largeTitle.bold())
            Text("A Badger keeps raising the stakes on a commitment — a ladder of increasingly insistent alerts — until you mark it done. It's meant to be hard to ignore.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Get started") { step = 1 }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var notificationsStep: some View {
        permissionStep(
            icon: "bell.fill", title: "Notifications",
            rationale: "The gentler rungs of a ladder are notifications. BadgerMe needs permission to send them.",
            allowed: permissions.notifications.isAllowed,
            primaryTitle: "Allow Notifications",
            request: { await permissions.requestNotifications() },
            advance: { step = 2 })
    }

    private var alarmsStep: some View {
        permissionStep(
            icon: "alarm.fill", title: "Alarms",
            rationale: "The loudest rungs are alarms — so BadgerMe can reach you even on silent or during a Focus. This is what makes a Badger hard to ignore.",
            allowed: permissions.alarms == .authorized,
            primaryTitle: "Allow Alarms",
            request: { _ = await permissions.requestAlarms() },
            advance: onComplete)
    }

    @ViewBuilder
    private func permissionStep(icon: String, title: String, rationale: String, allowed: Bool,
                                primaryTitle: String, request: @escaping () async -> Void,
                                advance: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title.bold())
            Text(rationale).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if allowed {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
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
