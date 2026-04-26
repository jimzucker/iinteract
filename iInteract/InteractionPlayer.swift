//
//  InteractionPlayer.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Foundation
import AVFoundation

/// Plays an Interaction's boy/girl audio for a panel view controller. Owns the
/// AVAudioPlayer lifecycle so the calling VC doesn't have to. Returns the
/// duration the caller should drive its overlay-fade animation with (with a
/// 1-second floor so taps always feel responsive).
final class InteractionPlayer {

    static let minimumAnimationDuration: TimeInterval = 1.0

    private var audioPlayer: AVAudioPlayer?

    @discardableResult
    func play(_ interaction: Interaction, voiceStyle: String, enabled: Bool) -> TimeInterval {
        let minimum = Self.minimumAnimationDuration
        guard enabled else { return minimum }

        // Stop anything still playing so taps overlap cleanly.
        audioPlayer?.stop()
        audioPlayer = nil

        // User-authored interactions can have only one of the two voices
        // recorded — fall back to the other rather than going silent. (A
        // listener with the girl preference still hears a boy-only custom
        // interaction, and vice versa.)
        let preferred: URL? = (voiceStyle == "girl") ? interaction.girlSound : interaction.boySound
        let fallback:  URL? = (voiceStyle == "girl") ? interaction.boySound  : interaction.girlSound
        guard let url = preferred ?? fallback else {
            print("InteractionPlayer: no audio recorded for \(interaction.name ?? "?")")
            return minimum
        }
        // For user files (not bundled), verify the path is on disk so we
        // surface a clearer error than AVAudioPlayer's generic OSStatus.
        if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
            print("InteractionPlayer: file missing at \(url.path)")
            return minimum
        }

        // .playback category routes through the speaker and plays even with the
        // iPhone silent switch on — required for a communication aid. The
        // session activation can fail (e.g. another app holds it) but that
        // shouldn't prevent us from trying to play.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("InteractionPlayer: AVAudioSession setup failed: \(error)")
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.prepareToPlay()
            player.play()
            return max(player.duration, minimum)
        } catch {
            print("InteractionPlayer: AVAudioPlayer failed for \(url.lastPathComponent): \(error)")
            return minimum
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
