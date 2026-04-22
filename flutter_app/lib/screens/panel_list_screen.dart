//
//  panel_list_screen.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/panel.dart';
import 'panel_detail_screen.dart';

class PanelListScreen extends StatefulWidget {
  const PanelListScreen({super.key});

  @override
  State<PanelListScreen> createState() => _PanelListScreenState();
}

class _PanelListScreenState extends State<PanelListScreen> {
  String _voiceStyle = 'girl';

  @override
  void initState() {
    super.initState();
    _loadVoicePreference();
  }

  Future<void> _loadVoicePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _voiceStyle = prefs.getString('voice_style') ?? 'girl';
    });
  }

  Future<void> _showVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice Style'),
        content: const Text('Select default voice'),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setString('voice_style', 'boy');
              setState(() => _voiceStyle = 'boy');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Boy'),
          ),
          TextButton(
            onPressed: () async {
              await prefs.setString('voice_style', 'girl');
              setState(() => _voiceStyle = 'girl');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Girl'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iInteract'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showVoiceSettings,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: panels.length,
        itemBuilder: (context, index) {
          final panel = panels[index];
          return _PanelTile(
            panel: panel,
            voiceStyle: _voiceStyle,
          );
        },
      ),
    );
  }
}

class _PanelTile extends StatelessWidget {
  final Panel panel;
  final String voiceStyle;
  const _PanelTile({required this.panel, required this.voiceStyle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PanelDetailScreen(panel: panel, voiceStyle: voiceStyle),
        ),
      ),
      child: Container(
        color: panel.color,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        height: MediaQuery.of(context).size.height / panels.length,
        alignment: Alignment.centerLeft,
        child: Text(
          panel.title,
          style: const TextStyle(
            fontSize: 40,
            fontFamily: 'HelveticaNeue',
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
