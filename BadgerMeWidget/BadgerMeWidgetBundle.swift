//
//  BadgerMeWidgetBundle.swift
//  BadgerMeWidget
//
//  Created by Amos Glenn on 7/6/26.
//

import WidgetKit
import SwiftUI

@main
struct BadgerMeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BadgerMeWidget()
        BadgerMeWidgetControl()
        BadgerMeWidgetLiveActivity()
    }
}
