import SwiftUI

/// Record / play / delete a profile voice intro (Hinge-style, max 30s).
/// Reuses the chat's VoiceRecorder.
struct VoiceIntroEditSection: View {
    @ObservedObject var profileVM: ProfileViewModel
    @StateObject private var recorder = VoiceRecorder()
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.rose)
                Text("Voice Intro")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                if profileVM.isUploadingVoice {
                    ProgressView().scaleEffect(0.7)
                }
            }

            Text("Let your voice do the talking — a 30-second hello in Sindhi or English")
                .font(.system(size: 12))
                .foregroundColor(colors.textMuted)

            if recorder.isRecording {
                Button {
                    stopAndUpload()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("Stop (\(max(0, 30 - recorder.seconds))s left)")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(AppTheme.error))
                }
                .onChange(of: recorder.seconds) { _, secs in
                    if secs >= 30 { stopAndUpload() }
                }
            } else if let url = profileVM.user.voiceIntroUrl {
                HStack(spacing: 10) {
                    VoiceIntroButton(url: url)
                    Button("Delete") { profileVM.deleteVoiceIntro() }
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.error)
                    Button("Re-record") {
                        Task { _ = await recorder.startRecording() }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.rose)
                }
            } else {
                Button {
                    Task { _ = await recorder.startRecording() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                        Text("Record voice intro")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.rose)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        Capsule()
                            .fill(AppTheme.rose.opacity(0.1))
                            .overlay(Capsule().stroke(AppTheme.rose.opacity(0.5), lineWidth: 1))
                    )
                }
            }
        }
    }

    private func stopAndUpload() {
        guard let result = recorder.stopRecording() else { return }
        if result.duration >= 1, let data = try? Data(contentsOf: result.url) {
            profileVM.uploadVoiceIntro(audioData: data)
        }
    }
}
