import Foundation

struct Alarm: Identifiable, Codable, Equatable {
    var id: UUID
    var label: String
    var hour: Int
    var minute: Int
    var weekdays: Set<Weekday>
    var sound: AlarmSound
    var songPersistentID: UInt64?
    var songTitle: String?
    var songAssetURLString: String?
    var songDuration: Double?
    var playbackStartTime: Double?
    var playbackLoopDuration: Double?
    var volume: Double
    var vibrateEnabled: Bool
    var vibrationPattern: VibrationPattern
    var vibrationStrength: Double
    var gentleWakeDuration: GentleWakeDuration
    var isEnabled: Bool
    var challenge: WakeChallenge

    init(
        id: UUID = UUID(),
        label: String = "Alarm",
        hour: Int = 7,
        minute: Int = 0,
        weekdays: Set<Weekday> = Set(Weekday.allCases),
        sound: AlarmSound = .pulse,
        songPersistentID: UInt64? = nil,
        songTitle: String? = nil,
        songAssetURLString: String? = nil,
        songDuration: Double? = nil,
        playbackStartTime: Double? = nil,
        playbackLoopDuration: Double? = nil,
        volume: Double = 0.85,
        vibrateEnabled: Bool = true,
        vibrationPattern: VibrationPattern = .alert,
        vibrationStrength: Double = 0.85,
        gentleWakeDuration: GentleWakeDuration = .off,
        isEnabled: Bool = true,
        challenge: WakeChallenge = .none
    ) {
        self.id = id
        self.label = label
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.sound = sound
        self.songPersistentID = songPersistentID
        self.songTitle = songTitle
        self.songAssetURLString = songAssetURLString
        self.songDuration = songDuration
        self.playbackStartTime = playbackStartTime
        self.playbackLoopDuration = playbackLoopDuration
        self.volume = volume
        self.vibrateEnabled = vibrateEnabled
        self.vibrationPattern = vibrationPattern
        self.vibrationStrength = vibrationStrength
        self.gentleWakeDuration = gentleWakeDuration
        self.isEnabled = isEnabled
        self.challenge = challenge
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case hour
        case minute
        case weekdays
        case sound
        case songPersistentID
        case songTitle
        case songAssetURLString
        case songDuration
        case playbackStartTime
        case playbackLoopDuration
        case volume
        case vibrateEnabled
        case vibrationPattern
        case vibrationStrength
        case gentleWakeDuration
        case isEnabled
        case challenge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        weekdays = try container.decode(Set<Weekday>.self, forKey: .weekdays)
        sound = try container.decode(AlarmSound.self, forKey: .sound)
        songPersistentID = try container.decodeIfPresent(UInt64.self, forKey: .songPersistentID)
        songTitle = try container.decodeIfPresent(String.self, forKey: .songTitle)
        songAssetURLString = try container.decodeIfPresent(String.self, forKey: .songAssetURLString)
        songDuration = try container.decodeIfPresent(Double.self, forKey: .songDuration)
        playbackStartTime = try container.decodeIfPresent(Double.self, forKey: .playbackStartTime)
        playbackLoopDuration = try container.decodeIfPresent(Double.self, forKey: .playbackLoopDuration)
        volume = try container.decode(Double.self, forKey: .volume)
        vibrateEnabled = try container.decode(Bool.self, forKey: .vibrateEnabled)
        vibrationPattern = try container.decode(VibrationPattern.self, forKey: .vibrationPattern)
        vibrationStrength = try container.decode(Double.self, forKey: .vibrationStrength)
        gentleWakeDuration = try container.decodeIfPresent(GentleWakeDuration.self, forKey: .gentleWakeDuration) ?? .off
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        challenge = try container.decode(WakeChallenge.self, forKey: .challenge)
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    var nextFireDate: Date? {
        let calendar = Calendar.current

        if weekdays.isEmpty {
            return calendar.nextDate(
                after: .now,
                matching: dateComponents,
                matchingPolicy: .nextTimePreservingSmallerComponents
            )
        }

        return weekdays.compactMap { weekday in
            var components = dateComponents
            components.weekday = weekday.rawValue
            return calendar.nextDate(
                after: .now,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents
            )
        }
        .min()
    }

    var formattedTime: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var repeatSummary: String {
        if weekdays.count == Weekday.allCases.count { return "Every day" }
        if weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Weekdays" }
        if weekdays == [.saturday, .sunday] { return "Weekends" }
        if weekdays.isEmpty { return "Once" }
        return Weekday.allCases
            .filter { weekdays.contains($0) }
            .map(\.shortTitle)
            .joined(separator: ", ")
    }

    var soundTitle: String {
        songTitle ?? sound.title
    }

    var effectivePlaybackStartTime: Double {
        max(0, playbackStartTime ?? 0)
    }

    var effectivePlaybackLoopDuration: Double {
        max(0, playbackLoopDuration ?? 0)
    }

    var hasClipLoop: Bool {
        effectivePlaybackLoopDuration > 0
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }
}

enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case pulse
    case bell
    case rise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pulse: return "Pulse"
        case .bell: return "Bell"
        case .rise: return "Rise"
        }
    }

    var fileName: String {
        switch self {
        case .pulse: return "pulse.wav"
        case .bell: return "bell.wav"
        case .rise: return "rise.wav"
        }
    }
}

enum WakeChallenge: String, Codable, CaseIterable, Identifiable {
    case none
    case tapHold
    case focusTaps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .tapHold: return "Hold to dismiss"
        case .focusTaps: return "Tap pattern"
        }
    }
}

enum GentleWakeDuration: Int, Codable, CaseIterable, Identifiable {
    case off = 0
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60
    case minutes5 = 300
    case minutes10 = 600

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .seconds15: return "15 seconds"
        case .seconds30: return "30 seconds"
        case .seconds60: return "60 seconds"
        case .minutes5: return "5 minutes"
        case .minutes10: return "10 minutes"
        }
    }

    var summary: String {
        switch self {
        case .off:
            return "Start alarms at the selected volume."
        default:
            return "Start quiet and rise to your selected volume."
        }
    }

    var duration: TimeInterval {
        TimeInterval(rawValue)
    }
}

enum VibrationPattern: String, Codable, CaseIterable, Identifiable {
    case alert
    case heartbeat
    case quick
    case rapid
    case sos
    case staccato
    case symphony

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alert: return "Alert"
        case .heartbeat: return "Heartbeat"
        case .quick: return "Quick"
        case .rapid: return "Rapid"
        case .sos: return "S.O.S."
        case .staccato: return "Staccato"
        case .symphony: return "Symphony"
        }
    }

    var pulseDelays: [Double] {
        switch self {
        case .alert:
            return [0.75]
        case .heartbeat:
            return [0.16, 0.82]
        case .quick:
            return [0.22, 0.95]
        case .rapid:
            return [0.18, 0.18, 0.18, 0.58]
        case .sos:
            return [0.16, 0.16, 0.56, 0.34, 0.34, 0.86]
        case .staccato:
            return [0.12, 0.12, 0.12, 0.82]
        case .symphony:
            return [0.22, 0.44, 0.22, 0.68]
        }
    }
}
