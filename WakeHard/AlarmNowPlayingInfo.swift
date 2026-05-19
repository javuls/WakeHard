import Foundation
import MediaPlayer
import UIKit

/// Owns the system `MPNowPlayingInfoCenter` while an alarm is firing with a
/// Music-library song.
///
/// Why this exists: `MPMusicPlayerController.applicationMusicPlayer` auto-publishes
/// the song's title/artist/artwork to Now Playing, and iOS shows Now Playing
/// in the Dynamic Island compact slot in preference to our Live Activity.
/// That's why album artwork was appearing instead of the green alarm icon.
///
/// This helper replaces that artwork with a custom alarm icon, and re-applies
/// it whenever the music player tries to clobber it back.
@MainActor
enum AlarmNowPlayingInfo {
    private static var observer: NSObjectProtocol?
    private static var currentLabel: String?
    private static var cachedArtwork: MPMediaItemArtwork?

    /// Begin overriding Now Playing for an alarm. Idempotent; safe to call
    /// multiple times in quick succession.
    static func startForAlarm(label: String) {
        currentLabel = label
        applyInfo()

        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: MPMusicPlayerController.applicationMusicPlayer,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    // If the music player swapped in a new item it will have
                    // replaced our Now Playing info — push ours back.
                    AlarmNowPlayingInfo.applyInfo()
                }
            }
        }
    }

    /// Tear down: stop reapplying our info and clear what we set.
    static func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        currentLabel = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private static func applyInfo() {
        guard let label = currentLabel else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: label.isEmpty ? "Alarm" : label,
            MPMediaItemPropertyArtist: "WakeHard",
            MPMediaItemPropertyArtwork: artwork()
        ]
    }

    private static func artwork() -> MPMediaItemArtwork {
        if let cachedArtwork { return cachedArtwork }
        let bounds = CGSize(width: 600, height: 600)
        let art = MPMediaItemArtwork(boundsSize: bounds) { requestedSize in
            let renderer = UIGraphicsImageRenderer(size: requestedSize)
            return renderer.image { ctx in
                UIColor.black.setFill()
                ctx.fill(CGRect(origin: .zero, size: requestedSize))

                let pointSize = min(requestedSize.width, requestedSize.height) * 0.6
                let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
                guard let symbol = UIImage(systemName: "alarm.waves.left.and.right.fill",
                                           withConfiguration: config)?
                    .withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
                else { return }

                let iconSize = symbol.size
                let iconRect = CGRect(
                    x: (requestedSize.width - iconSize.width) / 2,
                    y: (requestedSize.height - iconSize.height) / 2,
                    width: iconSize.width,
                    height: iconSize.height
                )
                symbol.draw(in: iconRect)
            }
        }
        cachedArtwork = art
        return art
    }
}
