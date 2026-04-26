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

        let url: URL? = (voiceStyle == "girl") ? interaction.girlSound : interaction.boySound
        guard let url = url else {
            print("InteractionPlayer: no \(voiceStyle) sound for \(interaction.name ?? "?")")
            return minimum
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
