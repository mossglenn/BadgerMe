//
//  ConsoleFormatting.swift
//  BadgerMe — small presentation helpers shared by the console views (§16, M7 CP3).
//

import SwiftUI
import BadgerKit

enum ConsoleFormat {
    /// A rung's delay-from-start as a short label: "now", "5m", "45m", "1h30m".
    static func delay(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s <= 0 { return "now" }
        let m = s / 60, h = m / 60, rem = m % 60
        if h > 0 { return rem > 0 ? "\(h)h\(rem)m" : "\(h)h" }
        return "\(m)m"
    }

    /// A prominence as a plain-spoken label (paired with a symbol, never colour-only).
    static func prominence(_ p: BadgerKit.Prominence?) -> String {
        switch p {
        case .passive:       return "Quiet"
        case .active:        return "Notify"
        case .timeSensitive: return "Time-sensitive"
        case .breakthrough:  return "Alarm"
        case nil:            return "—"
        }
    }

    static func prominenceSymbol(_ p: BadgerKit.Prominence?) -> String {
        switch p {
        case .breakthrough:  return "alarm.fill"
        case .timeSensitive: return "bell.badge.fill"
        case .active:        return "bell.fill"
        default:             return "bell"
        }
    }

    /// Humanise a raw EventKind string ("levelFired" → "Level fired") — EventKind is module-internal,
    /// so the history timeline renders from the public `kindRaw`. Promote EventKind to public if a
    /// richer typed rendering is wanted later (§7 note).
    static func humanize(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            if ch.isUppercase { out.append(" ") }
            out.append(ch)
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}

/// A compact read-only summary of a ladder's rungs (used in create + detail).
struct LadderPreview: View {
    let preset: LadderPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(preset.rungs, id: \.index) { rung in
                let action = rung.actions.first
                HStack(spacing: 8) {
                    Text(ConsoleFormat.delay(rung.delay))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .leading)
                    Image(systemName: ConsoleFormat.prominenceSymbol(action?.prominence))
                        .foregroundStyle(action?.prominence == .breakthrough ? Color.red : .secondary)
                        .imageScale(.small)
                    Text(ConsoleFormat.prominence(action?.prominence)).font(.caption)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Snooze budget: \(preset.defaultMaxSnoozeCount)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
