import MediaPlayer
import SwiftUI
import UIKit

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var soundManager: SoundManager
    @State private var alarm: Alarm
    @State private var selectedDate: Date
    @State private var showingSongNote = false
    @State private var songNoteMessage = ""
    @State private var showingMusicPicker = false
    @State private var showingGentleWakePicker = false
    @State private var showingSnoozePicker = false
    @State private var showingDiscardConfirmation = false
    @State private var showingRequiredFieldsAlert = false
    @State private var requiredFieldsMessage = ""
    private let originalAlarm: Alarm

    let onSave: (Alarm) -> Void

    init(alarm: Alarm, onSave: @escaping (Alarm) -> Void) {
        _alarm = State(initialValue: alarm)
        var components = DateComponents()
        components.hour = alarm.hour
        components.minute = alarm.minute
        _selectedDate = State(initialValue: Calendar.current.date(from: components) ?? .now)
        originalAlarm = alarm
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        DatePicker("Alarm time", selection: $selectedDate, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .padding(.vertical, 6)
                            .background(AppTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        EditorSection(title: "Schedule") {
                            HStack {
                                Text(scheduleTitle)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(AppTheme.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Spacer()

                                Button {
                                    alarm.weekdays = isDaily ? [] : Set(Weekday.allCases)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isDaily ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundStyle(isDaily ? AppTheme.accent : AppTheme.secondary)
                                        Text("Daily")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(AppTheme.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            WeekdaySelector(selection: $alarm.weekdays)
                        }

                        EditorSection(title: alarm.songTitle == nil ? "Sound" : "Backup Sound") {
                            Picker("Tone", selection: $alarm.sound) {
                                ForEach(AlarmSound.allCases) { sound in
                                    Text(sound.title).tag(sound)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                Button {
                                    if isPreviewActive {
                                        soundManager.stop()
                                    } else {
                                        soundManager.play(alarm: alarm, loops: false)
                                    }
                                } label: {
                                    Label(
                                        isPreviewActive ? "Stop" : "Preview",
                                        systemImage: isPreviewActive ? "stop.fill" : "play.fill"
                                    )
                                }
                                .buttonStyle(SecondaryButtonStyle())

                                Button {
                                    MPMediaLibrary.requestAuthorization { status in
                                        DispatchQueue.main.async {
                                            if status == .authorized {
                                                showingMusicPicker = true
                                            } else {
                                                songNoteMessage = "Allow Media & Apple Music access in Settings to choose local songs."
                                                showingSongNote = true
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Songs", systemImage: "music.note")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }

                            if let songTitle = alarm.songTitle {
                                HStack {
                                    Label(songTitle, systemImage: "music.note")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        removeSelectedSong()
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(IconButtonStyle())
                                    .accessibilityLabel("Remove selected song")
                                }

                                Text("\(alarm.sound.title) will play if the selected song is unavailable.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.secondary)
                            }

                            if alarm.songTitle != nil {
                                Toggle("Loop clip", isOn: Binding(
                                    get: { alarm.hasClipLoop },
                                    set: { isOn in
                                        alarm.playbackLoopDuration = isOn ? min(20, max(5, songDurationLimit / 8)) : nil
                                        alarm.playbackStartTime = isOn ? alarm.effectivePlaybackStartTime : nil
                                    }
                                ))
                                .tint(AppTheme.accent)

                                if alarm.hasClipLoop {
                                    TrimRangeControl(
                                        start: playbackStartBinding,
                                        end: playbackEndBinding,
                                        playhead: playbackScrubBinding,
                                        duration: songDurationLimit,
                                        isPreviewing: soundManager.isPreviewPlaying
                                    )
                                }
                            }
                        }

                        EditorSection(title: "Volume") {
                            HStack(spacing: 12) {
                                Image(systemName: "speaker.fill")
                                    .foregroundStyle(AppTheme.secondary)
                                Slider(value: $alarm.volume, in: 0.1...1)
                                    .tint(AppTheme.accent)
                                    .onChange(of: alarm.volume) { _, _ in
                                        // Stop the preview as soon as the user
                                        // moves the volume slider so they can
                                        // reset and hear it at the new level.
                                        if isPreviewActive {
                                            soundManager.stop()
                                        }
                                    }
                                Text("\(Int(alarm.volume * 100))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }

                        EditorSection(title: "Gentle Wake-Up") {
                            Button {
                                showingGentleWakePicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Ramp volume")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(AppTheme.primary)
                                        Text(alarm.gentleWakeDuration.summary)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(AppTheme.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Text(alarm.gentleWakeDuration.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(AppTheme.muted)
                                }
                                // Stretch the label so the whole row, including
                                // the Spacer gap, becomes the hit area.
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        EditorSection(title: "Vibration") {
                            Toggle("Vibrate", isOn: $alarm.vibrateEnabled)
                                .tint(AppTheme.accent)

                            if alarm.vibrateEnabled {
                                Picker("Pattern", selection: $alarm.vibrationPattern) {
                                    ForEach(VibrationPattern.allCases) { pattern in
                                        Text(pattern.title).tag(pattern)
                                    }
                                }
                                .pickerStyle(.menu)

                                HStack(spacing: 12) {
                                    Image(systemName: "iphone.radiowaves.left.and.right")
                                        .foregroundStyle(AppTheme.secondary)
                                    Slider(value: $alarm.vibrationStrength, in: 0.15...1)
                                        .tint(AppTheme.accent)
                                    Text("\(Int(alarm.vibrationStrength * 100))")
                                        .font(.system(size: 13, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(AppTheme.secondary)
                                        .frame(width: 30, alignment: .trailing)
                                }

                                Button {
                                    VibrationManager.shared.preview(
                                        pattern: alarm.vibrationPattern,
                                        strength: alarm.vibrationStrength
                                    )
                                } label: {
                                    Label("Preview Vibration", systemImage: "waveform.path")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }

                        EditorSection(title: "Dismiss") {
                            Picker("Challenge", selection: $alarm.challenge) {
                                ForEach(WakeChallenge.allCases) { challenge in
                                    Text(dismissTitle(for: challenge)).tag(challenge)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        EditorSection(title: "Snooze") {
                            Button {
                                showingSnoozePicker = true
                            } label: {
                                snoozeButtonLabel
                            }
                            .buttonStyle(.plain)
                        }

                        EditorSection(title: "Label") {
                            TextField("Alarm", text: $alarm.label)
                                .textInputAutocapitalization(.words)
                                .font(.system(size: 16, weight: .medium))
                                .padding(12)
                                .background(AppTheme.panelSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        attemptDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAlarm()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingMusicPicker) {
                MusicPickerView { item in
                    soundManager.stop()
                    alarm.songPersistentID = item.persistentID
                    alarm.songTitle = item.title ?? "Selected song"
                    alarm.songAssetURLString = item.assetURL?.absoluteString
                    alarm.songDuration = item.playbackDuration > 0 ? item.playbackDuration : nil
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingGentleWakePicker) {
                GentleWakePickerSheet(selection: $alarm.gentleWakeDuration)
                    .presentationDetents([.height(430)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSnoozePicker) {
                SnoozeEditorView(alarm: $alarm)
            }
            .alert("Music access is needed", isPresented: $showingSongNote) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(songNoteMessage)
            }
            .alert("Finish alarm setup", isPresented: $showingRequiredFieldsAlert) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(requiredFieldsMessage)
            }
            .confirmationDialog(
                "Discard unsaved changes?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    discardChanges()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your changes to this alarm will be lost.")
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .background(
                DismissAttemptGuard(isDisabled: hasUnsavedChanges) {
                    showingDiscardConfirmation = true
                }
            )
        }
        .preferredColorScheme(.dark)
    }

    private var currentDraft: Alarm {
        var draft = alarm
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedDate)
        draft.hour = components.hour ?? draft.hour
        draft.minute = components.minute ?? draft.minute
        return draft
    }

    private var hasUnsavedChanges: Bool {
        currentDraft != originalAlarm
    }

    private var isPreviewActive: Bool {
        soundManager.isPreviewPlaying || soundManager.isPreviewPaused
    }

    private var isDaily: Bool {
        alarm.weekdays.count == Weekday.allCases.count
    }

    private var scheduleTitle: String {
        if isDaily { return "Daily" }
        if alarm.weekdays.isEmpty { return "One-time" }
        return Weekday.allCases
            .filter { alarm.weekdays.contains($0) }
            .map(\.shortTitle)
            .joined(separator: ", ")
    }

    private var songDurationLimit: Double {
        max(30, alarm.songDuration ?? 240)
    }

    private var clipStartUpperBound: Double {
        max(0, songDurationLimit - 5)
    }

    private var clipLengthUpperBound: Double {
        max(5, min(90, songDurationLimit - alarm.effectivePlaybackStartTime))
    }

    private var playbackStartBinding: Binding<Double> {
        Binding(
            get: { min(alarm.effectivePlaybackStartTime, clipStartUpperBound) },
            set: { newValue in
                alarm.playbackStartTime = min(max(0, newValue), clipStartUpperBound)
                if alarm.effectivePlaybackLoopDuration > clipLengthUpperBound {
                    alarm.playbackLoopDuration = clipLengthUpperBound
                }
            }
        )
    }

    private var playbackLengthBinding: Binding<Double> {
        Binding(
            get: { min(max(5, alarm.effectivePlaybackLoopDuration), clipLengthUpperBound) },
            set: { newValue in
                alarm.playbackLoopDuration = min(max(5, newValue), clipLengthUpperBound)
            }
        )
    }

    private var playbackEndBinding: Binding<Double> {
        Binding(
            get: {
                min(songDurationLimit, alarm.effectivePlaybackStartTime + alarm.effectivePlaybackLoopDuration)
            },
            set: { newValue in
                let start = alarm.effectivePlaybackStartTime
                let end = min(songDurationLimit, max(start + 5, newValue))
                alarm.playbackLoopDuration = end - start
            }
        )
    }

    private var playbackScrubBinding: Binding<Double> {
        Binding(
            get: {
                isPreviewActive
                    ? min(playbackEndBinding.wrappedValue, max(alarm.effectivePlaybackStartTime, soundManager.previewPlaybackTime))
                    : alarm.effectivePlaybackStartTime
            },
            set: { newValue in
                guard !isPreviewActive else { return }
                alarm.playbackStartTime = min(max(0, newValue), clipStartUpperBound)
                if alarm.effectivePlaybackLoopDuration > clipLengthUpperBound {
                    alarm.playbackLoopDuration = clipLengthUpperBound
                }
            }
        )
    }

    private var snoozeButtonLabel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Snooze Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text(alarm.snoozeEnabled ? "Every \(alarm.snoozeInterval.title), up to \(alarm.snoozeCount.title)" : "Disabled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.muted)
        }
        // Stretch the label so the whole row, including the Spacer gap,
        // becomes the hit area of the surrounding Button.
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func dismissTitle(for challenge: WakeChallenge) -> String {
        challenge == .none ? "Choose" : challenge.title
    }

    private func saveAlarm() {
        let draft = currentDraft
        guard missingRequiredFields(in: draft).isEmpty else {
            requiredFieldsMessage = "Choose a dismiss style before saving this alarm."
            showingRequiredFieldsAlert = true
            return
        }

        onSave(draft)
        soundManager.stop()
        VibrationManager.shared.stop()
        dismiss()
    }

    private func missingRequiredFields(in alarm: Alarm) -> [String] {
        alarm.challenge == .none ? ["Dismiss style"] : []
    }

    private func formatTime(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            showingDiscardConfirmation = true
            return
        }
        discardChanges()
    }

    private func discardChanges() {
        soundManager.stop()
        VibrationManager.shared.stop()
        dismiss()
    }

    private func removeSelectedSong() {
        soundManager.stop()
        alarm.songPersistentID = nil
        alarm.songTitle = nil
        alarm.songAssetURLString = nil
        alarm.songDuration = nil
        alarm.playbackStartTime = nil
        alarm.playbackLoopDuration = nil
    }
}

private struct DismissAttemptGuard: UIViewControllerRepresentable {
    let isDisabled: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.isDisabled = isDisabled
        context.coordinator.onAttempt = onAttempt

        DispatchQueue.main.async {
            uiViewController.parent?.presentationController?.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isDisabled: isDisabled, onAttempt: onAttempt)
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDisabled: Bool
        var onAttempt: () -> Void

        init(isDisabled: Bool, onAttempt: @escaping () -> Void) {
            self.isDisabled = isDisabled
            self.onAttempt = onAttempt
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !isDisabled
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            guard isDisabled else { return }
            onAttempt()
        }
    }
}

private struct TrimRangeControl: View {
    @Binding var start: Double
    @Binding var end: Double
    @Binding var playhead: Double
    let duration: Double
    let isPreviewing: Bool

    @State private var startDragBase: Double?
    @State private var endDragBase: Double?
    @State private var playheadDragBase: Double?
    @State private var isStartDragging = false
    @State private var isEndDragging = false
    @State private var isPlayheadDragging = false

    private let handleWidth = 26.0
    private let minimumGap = 5.0

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width - handleWidth)
            let startX = xPosition(for: start, width: width)
            let endX = xPosition(for: end, width: width)
            let clampedPlayhead = min(end, max(start, playhead))
            let playheadX = xPosition(for: clampedPlayhead, width: width)
            let playedWidth = max(0, min(endX, playheadX) - startX)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.panelSecondary)
                    .frame(height: 40)
                    .offset(x: handleWidth / 2, y: 36)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: max(0, endX - startX), height: 40)
                    .offset(x: startX + handleWidth / 2, y: 36)

                Capsule()
                    .fill(AppTheme.secondary.opacity(0.2))
                    .frame(width: max(0, endX - startX), height: 3)
                    .offset(x: startX + handleWidth / 2, y: 55)

                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: playedWidth, height: 3)
                    .offset(x: startX + handleWidth / 2, y: 55)
                    .opacity(isPreviewing ? 1 : 0)

                waveformMarks(width: width)
                    .offset(x: handleWidth / 2, y: 42)

                handle(label: formatTime(start), side: .left, isActive: isStartDragging)
                    .offset(x: startX, y: 0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard isHorizontalDrag(value) || isStartDragging else { return }
                                isStartDragging = true
                                if startDragBase == nil { startDragBase = start }
                                let delta = duration * value.translation.width / width
                                let proposed = (startDragBase ?? start) + delta
                                start = min(max(0, proposed), max(0, end - minimumGap))
                                playhead = start
                            }
                            .onEnded { _ in
                                startDragBase = nil
                                isStartDragging = false
                            }
                    )

                handle(label: formatTime(end), side: .right, isActive: isEndDragging)
                    .offset(x: endX, y: 0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard isHorizontalDrag(value) || isEndDragging else { return }
                                isEndDragging = true
                                if endDragBase == nil { endDragBase = end }
                                let delta = duration * value.translation.width / width
                                let proposed = (endDragBase ?? end) + delta
                                end = min(duration, max(start + minimumGap, proposed))
                            }
                            .onEnded { _ in
                                endDragBase = nil
                                isEndDragging = false
                            }
                    )

                playheadView(label: formatTime(clampedPlayhead))
                    .offset(x: playheadX + handleWidth / 2, y: 2)
                    .opacity(isPreviewing ? 1 : 0)
                    .allowsHitTesting(!isPreviewing)

                Rectangle()
                    .fill(AppTheme.primary)
                    .frame(width: 2, height: 46)
                    .offset(x: playheadX + handleWidth / 2, y: 32)
                    .opacity(0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isPreviewing else { return }
                                guard isHorizontalDrag(value) || isPlayheadDragging else { return }
                                isPlayheadDragging = true
                                if playheadDragBase == nil { playheadDragBase = playhead }
                                let delta = duration * value.translation.width / width
                                let proposed = (playheadDragBase ?? playhead) + delta
                                playhead = min(end, max(start, proposed))
                            }
                            .onEnded { _ in
                                playheadDragBase = nil
                                isPlayheadDragging = false
                            }
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        guard !isPreviewing else { return }
                        guard isHorizontalDrag(value) else { return }
                        playhead = min(end, max(start, timeValue(for: value.location.x - handleWidth / 2, width: width)))
                    }
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isStartDragging)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isEndDragging)
            .animation(.easeOut(duration: 0.12), value: isPreviewing)
        }
        .frame(height: 102)
    }

    private func waveformMarks(width: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<32, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.secondary.opacity(0.55))
                    .frame(width: max(2, (width - 124) / 32), height: markHeight(index))
            }
        }
        .frame(width: width, height: 28, alignment: .center)
    }

    private enum HandleSide {
        case left
        case right
    }

    private func handle(label: String, side: HandleSide, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isActive ? AppTheme.primary : AppTheme.secondary)
                .frame(width: 54)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(AppTheme.accent)
                .frame(width: isActive ? 20 : 5, height: isActive ? 58 : 44)
                .overlay {
                    Image(systemName: side == .left ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .opacity(isActive ? 1 : 0)
                }
        }
        .frame(width: handleWidth)
    }

    private func playheadView(label: String) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.panel.opacity(0.92))
                .overlay(
                    Capsule().stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(Capsule())
            Rectangle()
                .fill(AppTheme.primary)
                .frame(width: 2, height: 50)
        }
        .frame(width: 1)
    }

    private func xPosition(for time: Double, width: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(width, max(0, width * time / duration))
    }

    private func timeValue(for x: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(duration, max(0, duration * x / width))
    }

    private func isHorizontalDrag(_ value: DragGesture.Value) -> Bool {
        let horizontal = abs(value.translation.width)
        let vertical = abs(value.translation.height)
        return horizontal > 8 && horizontal > vertical * 1.35
    }

    private func markHeight(_ index: Int) -> Double {
        let pattern = [14.0, 22.0, 10.0, 28.0, 18.0, 24.0, 12.0, 20.0]
        return pattern[index % pattern.count]
    }

    private func formatTime(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .textCase(.uppercase)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GentleWakePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: GentleWakeDuration

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Gentle Wake-Up")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primary)
                    Text("Gradually raises alarm volume from silent to your selected volume over the time you choose.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    ForEach(GentleWakeDuration.allCases) { duration in
                        Button {
                            selection = duration
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(duration.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.primary)
                                    Text(duration.summary)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppTheme.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: selection == duration ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(selection == duration ? AppTheme.accent : AppTheme.muted)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 48)
                            .background(AppTheme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selection == duration ? AppTheme.accent.opacity(0.45) : AppTheme.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}

private struct WeekdaySelector: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Weekday.allCases) { weekday in
                Button {
                    if selection.contains(weekday) {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(weekday.shortTitle.prefix(1))
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .foregroundStyle(selection.contains(weekday) ? .black : AppTheme.secondary)
                .background(selection.contains(weekday) ? AppTheme.accent : AppTheme.panelSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(weekday.shortTitle)
            }
        }
    }
}
