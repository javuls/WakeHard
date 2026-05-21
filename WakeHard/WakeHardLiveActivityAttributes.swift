import ActivityKit
import Foundation

enum WakeHardLiveActivityMode: String, Codable, Hashable {
    case nextAlarm
    case skippedOnce
    case ringing
    case snoozed
}

struct WakeHardSnoozeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mode: WakeHardLiveActivityMode
        var fireDate: Date?
        var remainingSnoozes: Int?
    }

    var alarmID: String
    var alarmLabel: String
}
