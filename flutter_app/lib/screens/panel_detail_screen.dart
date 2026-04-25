//
//  panel_detail_screen.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/panel.dart';

class PanelDetailScreen extends StatefulWidget {
  final Panel panel;
  final String voiceStyle;
  const PanelDetailScreen({super.key, required this.panel, required this.voiceStyle});

  @override
  State<PanelDetailScreen> createState() => _PanelDetailScreenState();
}

class _PanelDetailScreenState extends State<PanelDetailScreen> {
  final AudioPlayer _player = AudioPlayer();
  Interaction? _overlay;
  bool _overlayVisible = false;

  @override
  void initState() {
    super.initState();
    _configureAudioSession();
  }

  Future<void> _configureAudioSession() async {
    // Use playback category so audio plays even with the iPhone silent switch
    // on — this is a communication aid that must always speak.
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {},
        ),
        android: AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.assistanceAccessibility,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
    } catch (e) {
      debugPrint('iInteract setAudioContext failed: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _onTap(Interaction interaction) async {
    // Mount the overlay at opacity 0 first, then flip to 1 next frame so
    // AnimatedOpacity actually animates instead of appearing instantly.
    setState(() {
      _overlay = interaction;
      _overlayVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _overlayVisible = true);
    });
    final sound = widget.voiceStyle == 'boy' ? interaction.boySound : interaction.girlSound;
    final assetPath = sound.replaceFirst('assets/', '');
    try {
      await _player.stop();
      await _player.play(AssetSource(assetPath));
    } catch (e, st) {
      debugPrint('iInteract audio error for $assetPath: $e\n$st');
    }
  }

  void _hideOverlay() {
    setState(() => _overlayVisible = false);
  }

  void _onOverlayFadeEnd() {
    if (!_overlayVisible && mounted) {
      setState(() => _overlay = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactions = widget.panel.interactions;
    return Scaffold(
      backgroundColor: widget.panel.color,
      appBar: AppBar(
        backgroundColor: widget.panel.color,
        title: Text(
          '${widget.panel.title} ...',
          style: const TextStyle(
            color: Colors.black,
            fontFamily: 'HelveticaNeue-Bold',
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          _buildGrid(interactions),
          if (_overlay != null)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_overlayVisible,
                child: GestureDetector(
                  onTap: _hideOverlay,
                  child: AnimatedOpacity(
                    opacity: _overlayVisible ? 1.0 : 0.0,
                    duration: const Duration(seconds: 1),
                    curve: Curves.easeOut,
                    onEnd: _onOverlayFadeEnd,
                    child: Container(
                      color: widget.panel.color,
                      padding: const EdgeInsets.all(16),
                      child: SizedBox.expand(
                        child: Image.asset(_overlay!.imagePath, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Interaction> interactions) {
    const spacing = 16.0;
    const cols = 2;
    final rowCount = (interactions.length + cols - 1) ~/ cols;
    return Padding(
      padding: const EdgeInsets.all(spacing),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final byWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
          final byHeight = (constraints.maxHeight - spacing * (rowCount - 1)) / rowCount;
          final cellSize = byWidth < byHeight ? byWidth : byHeight;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < rowCount; r++) ...[
                  if (r > 0) const SizedBox(height: spacing),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < cols; c++) ...[
                        if (c > 0) const SizedBox(width: spacing),
                        SizedBox(
                          width: cellSize,
                          height: cellSize,
                          child: r * cols + c < interactions.length
                              ? GestureDetector(
                                  onTap: () => _onTap(interactions[r * cols + c]),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                      interactions[r * cols + c].imagePath,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
