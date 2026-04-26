//
//  CustomPanelViewController.swift
//  iInteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import UIKit

/// Renders a user-authored panel (1–6 interactions) using a UICollectionView.
/// Built-in panels keep using the storyboard-driven PanelViewController so
/// their look stays byte-for-byte v1.x; user panels need a flexible grid that
/// the 4-button storyboard can't provide.
final class CustomPanelViewController: UIViewController,
                                       UICollectionViewDataSource,
                                       UICollectionViewDelegate,
                                       UICollectionViewDelegateFlowLayout {

    private static let cellIdentifier = "InteractionCell"
    private static let interItemSpacing: CGFloat = 8
    private static let sectionInset: CGFloat = 16

    private let panel: Panel
    var voiceEnabled: Bool
    var voiceStyle: String
    private let player = InteractionPlayer()

    var collectionView: UICollectionView!
    private var overlayImageView: UIImageView!

    init(panel: Panel, voiceEnabled: Bool = true, voiceStyle: String = "girl") {
        self.panel = panel
        self.voiceEnabled = voiceEnabled
        self.voiceStyle = voiceStyle
        super.init(nibName: nil, bundle: nil)
        self.title = panel.title + " ..."
    }

    required init?(coder: NSCoder) {
        fatalError("CustomPanelViewController is programmatic")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = panel.color

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Self.interItemSpacing
        layout.minimumLineSpacing = Self.interItemSpacing
        layout.sectionInset = UIEdgeInsets(top: Self.sectionInset,
                                           left: Self.sectionInset,
                                           bottom: Self.sectionInset,
                                           right: Self.sectionInset)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = panel.color
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(InteractionCell.self, forCellWithReuseIdentifier: Self.cellIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        overlayImageView = UIImageView()
        overlayImageView.contentMode = .scaleAspectFit
        overlayImageView.backgroundColor = panel.color
        overlayImageView.alpha = 0
        overlayImageView.isUserInteractionEnabled = true
        overlayImageView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(hideOverlay))
        )
        overlayImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayImageView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            overlayImageView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        })
    }

    @objc private func hideOverlay() {
        UIView.animate(withDuration: 0.3) { self.overlayImageView.alpha = 0 }
    }

    // MARK: UICollectionViewDataSource

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        min(panel.interactions.count, PanelStore.maxInteractionsPerUserPanel)
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: Self.cellIdentifier,
                                          for: indexPath) as! InteractionCell
        cell.imageView.image = panel.interactions[indexPath.item].picture
        return cell
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let interaction = panel.interactions[indexPath.item]
        overlayImageView.image = interaction.picture
        overlayImageView.alpha = 0
        let duration = player.play(interaction, voiceStyle: voiceStyle, enabled: voiceEnabled)
        UIView.animate(withDuration: duration, delay: 0.0, options: .curveEaseOut, animations: {
            self.overlayImageView.alpha = 1
        })
    }

    // MARK: UICollectionViewDelegateFlowLayout

    func collectionView(_ cv: UICollectionView,
                        layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        Self.cellSize(for: panel.interactions.count,
                      in: view.safeAreaLayoutGuide.layoutFrame.size)
    }

    /// Adaptive grid: 2 cols in portrait, 3 cols in landscape, square cells
    /// sized to the smaller of available width/row-count and height/col-count
    /// so 1–6 cells always fit on screen without scrolling.
    static func cellSize(for itemCount: Int, in available: CGSize) -> CGSize {
        guard itemCount > 0 else { return .zero }
        let isLandscape = available.width > available.height
        let cols = isLandscape ? 3 : 2
        let rows = max(1, Int(ceil(Double(itemCount) / Double(cols))))
        let availW = available.width - sectionInset * 2 - interItemSpacing * CGFloat(cols - 1)
        let availH = available.height - sectionInset * 2 - interItemSpacing * CGFloat(rows - 1)
        let side = min(availW / CGFloat(cols), availH / CGFloat(rows))
        return CGSize(width: max(side, 1), height: max(side, 1))
    }
}

// MARK: - Cell

private final class InteractionCell: UICollectionViewCell {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
