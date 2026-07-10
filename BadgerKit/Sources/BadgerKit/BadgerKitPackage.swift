//
//  BadgerKitPackage.swift
//  BadgerKit — the AppIntentsPackage marker for this package (M4, §4/§11).
//
//  All of BadgerMe's App Intents, entities, and queries live in this package. The App
//  Intents metadata extractor only discovers intents in a package when a consuming
//  target opts that package in via AppIntentsPackage.includedPackages. So each target
//  (the app and the widget extension) declares its own AppIntentsPackage conformer
//  returning `[BadgerKitPackage.self]`; this marker is what they reference. Without
//  this linkage, package-defined intents — including the AlarmKit secondaryIntent —
//  are absent from the app's generated metadata (the likely cause of prior
//  discoverability doubts).
//

#if os(iOS)
import AppIntents

public struct BadgerKitPackage: AppIntentsPackage {}
#endif
