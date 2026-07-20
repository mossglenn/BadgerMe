//
//  RungTiming.swift
//  BadgerKit — the incremental→absolute delay conversion (D8, M7 revision).
//
//  D8 changed: a stored RungSpec.delay is now the INCREMENTAL gap after the previous rung fires
//  (rung 0's gap is from the Badger's start). The reducer's `Rung.delay` remains ABSOLUTE from
//  start — its math and golden-path tests are unchanged — so we accumulate the gaps into a running
//  total here, at the single boundary (BadgerEngine.makeContext) where stored ladders become the
//  reducer's timing model. Because the reducer stays absolute, the last-rung repeat interval it
//  computes (gap preceding the last rung) equals the last rung's own incremental delay.
//

import Foundation

/// Accumulate incremental rung gaps into absolute-from-start `Rung`s (sorted by index).
func absoluteRungs(fromIncremental specs: [RungSpec]) -> [Rung] {
    var cumulative: TimeInterval = 0
    var result: [Rung] = []
    for spec in specs.sorted(by: { $0.index < $1.index }) {
        cumulative += spec.delay
        result.append(Rung(index: spec.index, delay: cumulative))
    }
    return result
}
