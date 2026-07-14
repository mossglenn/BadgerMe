//
//  AmbientPresentation.swift
//  BadgerKit — the ambient Live Activity's phase + pure presentation rules (§12).
//
//  Foundation-only and public (no ActivityKit, no #if os(iOS)) so that (1) the widget renders
//  from `BadgerActivityPhase` — `BadgerActivityAttributes.Phase` is a typealias to it — and
//  (2) the phase→label/flag logic is unit-testable on macOS via `swift test`, instead of
//  living in the iOS-only widget target where the earlier helpers couldn't be reached
//  (code review #11 — the same "extract the pure core from behind a framework boundary"
//  move as the AlarmKit snapshot diff).
//

import Foundation

/// The ambient Live Activity's presentation phase (§12) — one enum end to end after code
/// review #3: the reducer emits it directly and the controller sets it straight onto
/// ContentState (no translation). `overdue` is presentation-only — the widget applies it
/// when the activity goes stale, never emitted.
public enum BadgerActivityPhase: String, Codable, Hashable, Sendable {
    case armed, escalating, repeating, snoozed, done, stopped, overdue
}

/// Pure presentation rules shared by the widget and its tests (code review #11).
public enum AmbientPresentation {

    /// Phases where a passed staleDate means "overdue" (vs. terminal / snoozed, which don't).
    public static func isEscalating(_ phase: BadgerActivityPhase) -> Bool {
        switch phase {
        case .armed, .escalating, .repeating, .overdue: return true
        case .snoozed, .done, .stopped:                 return false
        }
    }

    /// Done / Snooze are offered while the Badger is non-terminal.
    public static func showsActions(_ phase: BadgerActivityPhase) -> Bool {
        switch phase {
        case .done, .stopped: return false
        default:              return true
        }
    }

    /// The status subtitle. A passed staleDate (`isStale`) flips escalating phases to the
    /// overdue message; otherwise it reads off the phase and the "k of n" ladder position.
    public static func statusLine(phase: BadgerActivityPhase, level: Int,
                                  totalLevels: Int, isStale: Bool) -> String {
        if isStale, isEscalating(phase) { return "Overdue — escalating" }
        switch phase {
        case .armed:      return "Armed"
        case .escalating: return "Level \(level + 1) of \(totalLevels)"
        case .repeating:  return "Repeating — level \(totalLevels) of \(totalLevels)"
        case .snoozed:    return "Snoozed"
        case .done:       return "Done"
        case .stopped:    return "Stopped"
        case .overdue:    return "Overdue — escalating"
        }
    }
}
