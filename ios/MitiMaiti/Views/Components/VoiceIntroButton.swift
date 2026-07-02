import SwiftUI
import AVFoundation

/// Tap-to-play pill for a profile's voice introduction (Hinge-style).
struct VoiceIntroButton: View {
    let url: String
    @State private var isPlaying = false
    @State private var player: AVPlayer?

    var body: some View {
        Button {
            if isPlaying {
                player?.pause()
                player = nil
                isPlaying = false
            } else if let audioUrl = URL(string: url) {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
                let item = AVPlayerItem(url: audioUrl)
                let p = AVPlayer(playerItem: item)
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { _ in
                    isPlaying = false
                    player = nil
                }
                p.play()
                player = p
                isPlaying = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                Text(isPlaying ? "Playing voice intro…" : "Play voice intro")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(AppTheme.rose)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppTheme.rose.opacity(0.12))
                    .overlay(Capsule().stroke(AppTheme.rose.opacity(0.4), lineWidth: 1))
            )
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
