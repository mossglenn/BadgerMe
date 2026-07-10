//
//  BadgerMeAppIntents.swift
//  BadgerMe (app target) — opts the BadgerKit App Intents package into the app's
//  generated App Intents metadata (M4, §4/§11).
//
//  All entities/queries/intents live in BadgerKit. The metadata extractor only
//  discovers them when the consuming target declares an AppIntentsPackage listing the
//  package. Declaring this type is the whole requirement (its conformance metadata is
//  always emitted); nothing references it directly.
//

import AppIntents
import BadgerKit

struct BadgerMeAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [BadgerKitPackage.self] }
}
