//
//  BadgerMeWidgetLiveActivity.swift
//  BadgerMeWidget
//
//  Created by Amos Glenn on 7/6/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BadgerMeWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct BadgerMeWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BadgerMeWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension BadgerMeWidgetAttributes {
    fileprivate static var preview: BadgerMeWidgetAttributes {
        BadgerMeWidgetAttributes(name: "World")
    }
}

extension BadgerMeWidgetAttributes.ContentState {
    fileprivate static var smiley: BadgerMeWidgetAttributes.ContentState {
        BadgerMeWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: BadgerMeWidgetAttributes.ContentState {
         BadgerMeWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: BadgerMeWidgetAttributes.preview) {
   BadgerMeWidgetLiveActivity()
} contentStates: {
    BadgerMeWidgetAttributes.ContentState.smiley
    BadgerMeWidgetAttributes.ContentState.starEyes
}
