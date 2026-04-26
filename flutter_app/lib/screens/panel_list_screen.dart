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
import '../models/configuration_mode.dart';
import '../models/panel.dart';
import '../models/panel_loader.dart';
import '../models/panel_store.dart';
import 'panel_detail_screen.dart';
import 'panel_list_editor_screen.dart';
import 'pin_gate_screen.dart';

class PanelListScreen extends StatefulWidget {
  const PanelListScreen({super.key});

  @override
  State<PanelListScreen> createState() => _PanelListScreenState();
}

class _PanelListScreenState extends State<PanelListScreen> with WidgetsBindingObserver {
  String _voiceStyle = 'girl';
  ConfigurationMode _mode = ConfigurationMode.defaultMode;
  List<Panel> _panels = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read mode/panels on resume so changes from other surfaces (settings
    // sheet, editor flows) take effect without manual reload.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = await ConfigurationMode.current();
    final panels = await loadPanels(mode: mode);
    if (!mounted) return;
    setState(() {
      _voiceStyle = prefs.getString('voice_style') ?? 'girl';
      _mode = mode;
      _panels = panels;
    });
  }

  Future<void> _showSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        String voice = _voiceStyle;
        ConfigurationMode mode = _mode;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Voice', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'girl', label: Text('Girl')),
                        ButtonSegment(value: 'boy',  label: Text('Boy')),
                      ],
                      selected: {voice},
                      onSelectionChanged: (s) async {
                        voice = s.first;
                        await prefs.setString('voice_style', voice);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text('Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<ConfigurationMode>(
                      segments: const [
                        ButtonSegment(value: ConfigurationMode.defaultMode, label: Text('Default')),
                        ButtonSegment(value: ConfigurationMode.custom,      label: Text('Custom')),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) async {
                        mode = s.first;
                        await ConfigurationMode.set(mode);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Default: 7 built-in panels exactly as in v1.x.\n'
                      'Custom: hide / reorder built-ins and create your own panels.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    await _refresh();
  }

  Future<void> _openEditor() async {
    if (await PanelStore.shared.hasPin()) {
      final unlocked = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const PinGateScreen()),
      );
      if (unlocked != true) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PanelListEditorScreen()),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iInteract'),
        actions: [
          if (_mode == ConfigurationMode.custom)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _openEditor,
              tooltip: 'Edit panels',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _panels.isEmpty
          ? const Center(child: Text('No panels'))
          : Column(
              children: _panels
                  .map((panel) => Expanded(
                        child: _PanelTile(panel: panel, voiceStyle: _voiceStyle),
                      ))
                  .toList(),
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
