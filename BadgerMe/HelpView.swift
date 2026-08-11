//
//  HelpView.swift
//  BadgerMe — "How BadgerMe works": a Settings-reachable help screen (§16, D15).
//  In-character explanations of the mechanics and the trouble spots documented during
//  development: mark-done vs. dismiss (§14), max-snooze escalation (D6), last-rung
//  repeat (D4), ladder template-vs-bound-instance (§20), permission degradation (§17),
//  and the concurrency cap (D3). A future anchor for TipKit deep-links. Holds no engine
//  logic — a pure reference client of the app's vocabulary (L3).
//

import SwiftUI
import BadgerKit

struct HelpView: View {
    private struct Topic: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private let topics: [Topic] = [
        Topic(title: "What a Badger is",
              body: "A Badger reminds you of one thing you really want to remember to do. Each Badger has its own ladder of alerts that get harder and harder to miss or ignore. I start at the bottom, and I keep climbing and badgering you until you mark your task as done — that's the only thing that stops me."),
        Topic(title: "What a Ladder is",
              body: "A ladder is a stack of alerts separated by stretches of time. I climb up this ladder, waiting the required time before reminding you according to the next rung's instructions. Ladders in the library are reusable templates copied by each Badger when starting."),
        Topic(title: "Stopping a Badger vs. stopping an alert",
              body: "Swiping a notification away or tapping Stop on an alarm only silences that one alert. I'll be back with the next alert on the ladder. The one way to completely stop a Badger (other than buttons within the app) is to mark it Done. Dismissing is not done. I'm strict about this."),
        Topic(title: "Snoozing",
              body: "Snooze quiets me until the timer's up. Fair enough, and I'll be back with the same rung of the alert ladder. But too many snoozes is a sign you need my help, not my silence, so I'll jump up another rung and come back even harder. The snooze limits and durations live in Settings."),
        Topic(title: "Editing a ladder",
              body: "Ladders are created and edited in the library inside Settings. Changes to a ladder will affect all new and pending Badgers. Badgers that have already started are not affected since they have already made their copy of the ladder."),
        Topic(title: "When I reach the top",
              body: "I never quit. If I climb to the last rung and you still haven't completed your task, I'll keep repeating that last rung on its set interval. There's no waiting me out."),
        Topic(title: "Granting permissions",
              body: "Without notification permission I can't reach you at all. Without alarm permission I can only nudge softly — I won't break through silent mode or a Focus. You can grant either from Permissions in Settings, or in iOS Settings \u{25B8} BadgerMe."),
        Topic(title: "\u{201C}Paws are full\u{201D}",
              body: "There's a ceiling on how many Badgers can run at once, so your phone stays usable and I stay inside iOS's limits. If you hit it, resolve a Badger before starting another."),
        Topic(title: "Bossing me around by voice",
              body: "You can create, snooze, or resolve a Badger with Siri or the Shortcuts app — handy for automations like \u{201C}when I leave work, badger me to hit the gym.\u{201D} You don't have to open the BadgerMe app to put me to work."),
    ]

    var body: some View {
        List {
            ForEach(topics) { topic in
                Section {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(topic.title)
                            .font(.headline)
                        Text(topic.body)
                            .font(.badgerVoice(.callout))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Space.xxs)
                }
            }
        }
        .navigationTitle("How BadgerMe works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
