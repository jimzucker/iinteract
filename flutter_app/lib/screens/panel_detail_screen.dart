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
  double _overlayOpacity = 0.0;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _onTap(Interaction interaction) async {
    setState(() {
      _overlay = interaction;
      _overlayOpacity = 1.0;
    });
    final sound = widget.voiceStyle == 'boy' ? interaction.boySound : interaction.girlSound;
    await _player.stop();
    await _player.play(AssetSource(sound.replaceFirst('assets/', '')));
  }

  void _hideOverlay() {
    setState(() => _overlayOpacity = 0.0);
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
          GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: interactions.map((i) => GestureDetector(
              onTap: () => _onTap(i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(i.imagePath, fit: BoxFit.cover),
              ),
            )).toList(),
          ),
          if (_overlay != null)
            GestureDetector(
              onTap: _hideOverlay,
              child: AnimatedOpacity(
                opacity: _overlayOpacity,
                duration: const Duration(seconds: 1),
                curve: Curves.easeOut,
                child: Container(
                  color: widget.panel.color,
                  child: Center(
                    child: Image.asset(_overlay!.imagePath, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
