import AVFoundation
import Foundation
import Observation

enum SoundEffect: String, CaseIterable {
    case uiTap = "sfx_ui_tap"
    case collect = "sfx_collect"
    case deliver = "sfx_deliver"
    case dialogue = "sfx_dialogue"
    case toast = "sfx_toast"
    case sandStep = "sfx_sand_step"
}

/// Minecraft-style ambient music: play one track, wait a random silence gap, then another.
@Observable
@MainActor
final class AudioManager: NSObject {
    static let shared = AudioManager()

    private(set) var isMusicPlaying = false

    private var musicPlayer: AVAudioPlayer?
    private var sfxPlayers: [AVAudioPlayer] = []
    private var footstepTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var lastMusicName: String?
    private var musicEnabled = true
    private var soundEnabled = true
    private var isWalking = false
    private var sessionConfigured = false

    private let musicNames = ["music_dunes", "music_oasis", "music_campfire"]
    private let silenceRange: ClosedRange<Double> = 45...180
    private let audioSubdirectories = ["Resources/Audio", "Audio", nil] as [String?]

    private override init() {
        super.init()
    }

    func syncSettings(musicEnabled: Bool, soundEnabled: Bool) {
        let musicChanged = self.musicEnabled != musicEnabled
        let soundChanged = self.soundEnabled != soundEnabled
        self.musicEnabled = musicEnabled
        self.soundEnabled = soundEnabled

        if musicChanged {
            if musicEnabled {
                startAmbientMusic()
            } else {
                stopAmbientMusic()
            }
        }
        if soundChanged, !soundEnabled {
            stopFootsteps()
        } else if soundChanged, soundEnabled, isWalking {
            startFootsteps()
        }
    }

    func startAmbientMusic() {
        configureSessionIfNeeded()
        guard musicEnabled else {
            stopAmbientMusic()
            return
        }
        // Restart if nothing is actively playing (covers failed first attempts).
        if musicPlayer?.isPlaying == true { return }
        silenceTask?.cancel()
        silenceTask = nil
        playNextTrack()
    }

    func stopAmbientMusic() {
        silenceTask?.cancel()
        silenceTask = nil
        musicPlayer?.stop()
        musicPlayer = nil
        isMusicPlaying = false
    }

    func play(_ effect: SoundEffect, volume: Float = 1.0) {
        guard soundEnabled else { return }
        configureSessionIfNeeded()
        guard let url = resourceURL(named: effect.rawValue) else {
            #if DEBUG
            print("AudioManager: missing SFX \(effect.rawValue).wav")
            #endif
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.volume = min(1.0, volume)
            player.play()
            sfxPlayers.append(player)
            sfxPlayers.removeAll { !$0.isPlaying && $0 !== player }
        } catch {
            #if DEBUG
            print("AudioManager: failed to play \(effect.rawValue): \(error)")
            #endif
        }
    }

    /// Start/stop looping sand footsteps while the player walks.
    func setWalking(_ walking: Bool) {
        isWalking = walking
        if walking, soundEnabled {
            startFootsteps()
        } else {
            stopFootsteps()
        }
    }

    // MARK: - Private

    private func configureSessionIfNeeded() {
        do {
            let session = AVAudioSession.sharedInstance()
            // `.playback` ignores the hardware mute switch so game audio is audible.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sessionConfigured = true
        } catch {
            #if DEBUG
            print("AudioManager: session error \(error)")
            #endif
        }
    }

    private func resourceURL(named name: String) -> URL? {
        for sub in audioSubdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: sub) {
                return url
            }
        }
        return Bundle.main.url(forResource: name, withExtension: "wav")
    }

    private func playNextTrack() {
        guard musicEnabled else { return }
        configureSessionIfNeeded()
        guard let name = pickTrackName(),
              let url = resourceURL(named: name)
        else {
            #if DEBUG
            print("AudioManager: music file not found in bundle")
            #endif
            // Retry soon instead of waiting a full silence gap.
            scheduleRetry(after: 2)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.numberOfLoops = 0
            player.volume = 0.9
            player.prepareToPlay()
            musicPlayer = player
            lastMusicName = name
            let started = player.play()
            isMusicPlaying = started
            if !started {
                #if DEBUG
                print("AudioManager: play() returned false for \(name)")
                #endif
                scheduleRetry(after: 2)
            }
        } catch {
            #if DEBUG
            print("AudioManager: failed to load music \(name): \(error)")
            #endif
            scheduleRetry(after: 2)
        }
    }

    private func pickTrackName() -> String? {
        guard !musicNames.isEmpty else { return nil }
        var choices = musicNames
        if let last = lastMusicName, choices.count > 1 {
            choices.removeAll { $0 == last }
        }
        return choices.randomElement()
    }

    private func scheduleSilenceThenNext() {
        scheduleRetry(after: Double.random(in: silenceRange))
    }

    private func scheduleRetry(after delay: Double) {
        silenceTask?.cancel()
        guard musicEnabled else { return }
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.playNextTrack()
            }
        }
    }

    private func startFootsteps() {
        guard footstepTask == nil else { return }
        footstepTask = Task { [weak self] in
            // Slight delay so a one-frame nudge doesn't click.
            try? await Task.sleep(for: .milliseconds(40))
            while !Task.isCancelled {
                guard let self, self.isWalking, self.soundEnabled else { break }
                self.play(.sandStep, volume: 0.55)
                let interval = Double.random(in: 0.32...0.40)
                try? await Task.sleep(for: .seconds(interval))
            }
            await MainActor.run { self?.footstepTask = nil }
        }
    }

    private func stopFootsteps() {
        footstepTask?.cancel()
        footstepTask = nil
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === musicPlayer else { return }
            isMusicPlaying = false
            musicPlayer = nil
            scheduleSilenceThenNext()
        }
    }
}
