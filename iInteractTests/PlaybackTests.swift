//
//  PlaybackTests.swift
//  iInteractTests
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import XCTest
import UIKit
@testable import iInteract

final class InteractionPlayerTests: XCTestCase {

    func testDisabledVoiceReturnsMinimumDuration() {
        let player = InteractionPlayer()
        let interaction = Interaction(interactionName: "happy")
        let d = player.play(interaction, voiceStyle: "girl", enabled: false)
        XCTAssertEqual(d, InteractionPlayer.minimumAnimationDuration)
    }

    func testMissingSoundReturnsMinimumDuration() {
        let player = InteractionPlayer()
        let interaction = Interaction(id: UUID(), name: "nonexistent")
        // User-init Interaction has no boy/girl URLs; play() should bail safely.
        let d = player.play(interaction, voiceStyle: "girl", enabled: true)
        XCTAssertEqual(d, InteractionPlayer.minimumAnimationDuration)
    }

    func testBundledSoundReturnsAtLeastMinimumDuration() {
        let player = InteractionPlayer()
        // happy is bundled, so this loads the real MP3 from the test host bundle.
        let interaction = Interaction(interactionName: "happy")
        let d = player.play(interaction, voiceStyle: "girl", enabled: true)
        XCTAssertGreaterThanOrEqual(d, InteractionPlayer.minimumAnimationDuration)
        player.stop()
    }
}

final class CustomPanelViewControllerTests: XCTestCase {

    func testCellCountCappedAtSix() {
        let interactions = (1...10).map { Interaction(id: UUID(), name: "x\($0)") }
        let panel = Panel(title: "OverflowPanel",
                          color: .systemPink,
                          interactions: interactions,
                          isBuiltIn: false)
        let vc = CustomPanelViewController(panel: panel)
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.collectionView(vc.collectionView, numberOfItemsInSection: 0),
                       PanelStore.maxInteractionsPerUserPanel)
    }

    func testCellSizeSquareInPortrait() {
        // Portrait: width < height, so 2 cols, 3 rows for 6 items.
        let size = CustomPanelViewController.cellSize(
            for: 6,
            in: CGSize(width: 400, height: 800)
        )
        XCTAssertEqual(size.width, size.height, accuracy: 0.01,
                       "Cells must be square so the picture aspect-fills correctly")
        XCTAssertGreaterThan(size.width, 0)
    }

    func testCellSizeSquareInLandscape() {
        // Landscape: width > height, so 3 cols, 2 rows for 6 items.
        let size = CustomPanelViewController.cellSize(
            for: 6,
            in: CGSize(width: 800, height: 400)
        )
        XCTAssertEqual(size.width, size.height, accuracy: 0.01)
        XCTAssertGreaterThan(size.width, 0)
    }

    func testCellSizeFitsAllSixOnScreen() {
        let portraitSize = CGSize(width: 400, height: 800)
        let cell = CustomPanelViewController.cellSize(for: 6, in: portraitSize)
        // 2 cols × 3 rows × cell + insets must not exceed available size.
        let totalW = cell.width * 2 + 16 * 2 + 8 * 1
        let totalH = cell.height * 3 + 16 * 2 + 8 * 2
        XCTAssertLessThanOrEqual(totalW, portraitSize.width + 0.5)
        XCTAssertLessThanOrEqual(totalH, portraitSize.height + 0.5)
    }
}
