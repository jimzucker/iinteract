//
//  panel_list_editor_screen.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:flutter/material.dart';
import '../models/panel.dart';
import '../models/panel_store.dart';
import 'panel_editor_screen.dart';
import 'pin_setup_screen.dart';

/// In-app editor for the master panel list. Pushed when the user taps + in
/// custom mode. Lets the user toggle visibility of any panel (built-in or
/// user), drag to reorder, delete user panels, add new user panels, and
/// set/clear the PIN that gates entry to this screen.
class PanelListEditorScreen extends StatefulWidget {
  const PanelListEditorScreen({super.key});

  @override
  State<PanelListEditorScreen> createState() => _PanelListEditorScreenState();
}

class _PanelListEditorScreenState extends State<PanelListEditorScreen> {
  final PanelStore _store = PanelStore.shared;
  List<Panel> _panels = [];
  Set<String> _hidden = {};
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await _store.userPanels();
    for (final p in user) {
      await _store.hydrate(p);
    }
    final layout = await _store.layout();
    final ordered = _store.applyOrder([...builtInPanels(), ...user], layout);
    final hasPin = await _store.hasPin();
    if (!mounted) return;
    setState(() {
      _panels = ordered;
      _hidden = layout.hiddenIds;
      _hasPin = hasPin;
    });
  }

  Future<void> _toggleHidden(Panel p, bool visible) async {
    await _store.setHidden(!visible, p.id);
    setState(() {
      if (visible) {
        _hidden.remove(p.id);
      } else {
        _hidden.add(p.id);
      }
    });
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final p = _panels.removeAt(oldIndex);
    _panels.insert(newIndex, p);
    await _store.setOrder(_panels.map((p) => p.id).toList());
    setState(() {});
  }

  Future<void> _addPanel() async {
    final created = await Navigator.push<Panel?>(
      context,
      MaterialPageRoute(builder: (_) => const PanelEditorScreen()),
    );
    if (created != null) await _load();
  }

  Future<void> _editPanel(Panel p) async {
    if (p.isBuiltIn) return;
    final updated = await Navigator.push<Panel?>(
      context,
      MaterialPageRoute(builder: (_) => PanelEditorScreen(existing: p)),
    );
    if (updated != null) await _load();
  }

  Future<void> _confirmDelete(Panel p) async {
    if (p.isBuiltIn) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete panel?'),
        content: Text('"${p.title}" and its custom recordings will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final i in p.interactions) {
      if (!i.isBuiltIn) await _store.deleteInteractionAssets(i.id);
    }
    await _store.deletePanel(p.id);
    await _load();
  }

  Future<void> _openPinSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PinSetupScreen()),
    );
    await _load();
  }

  Future<void> _confirmClearPin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear PIN?'),
        content: const Text(
            'Anyone using this device will be able to open the editor without entering a PIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear PIN'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.clearPin();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Panels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New panel',
            onPressed: _addPanel,
          ),
        ],
      ),
      body: ReorderableListView.builder(
        // Footer: security section (not reorderable).
        itemCount: _panels.length,
        onReorder: _onReorder,
        footer: _SecuritySection(
          hasPin: _hasPin,
          onSetOrChange: _openPinSetup,
          onClear: _confirmClearPin,
        ),
        itemBuilder: (ctx, i) {
          final p = _panels[i];
          final visible = !_hidden.contains(p.id);
          return Container(
            key: ValueKey(p.id),
            color: p.color.withValues(alpha: 0.18),
            child: ListTile(
              title: Text(p.title),
              subtitle: Text(p.isBuiltIn ? 'Built-in' : 'Custom'),
              onTap: p.isBuiltIn ? null : () => _editPanel(p),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(value: visible, onChanged: (v) => _toggleHidden(p, v)),
                  if (!p.isBuiltIn)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDelete(p),
                      tooltip: 'Delete panel',
                    ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  final bool hasPin;
  final VoidCallback onSetOrChange;
  final VoidCallback onClear;
  const _SecuritySection({
    required this.hasPin,
    required this.onSetOrChange,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('security-footer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text('SECURITY', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(hasPin ? 'Change PIN' : 'Set PIN'),
          onTap: onSetOrChange,
          trailing: const Icon(Icons.chevron_right),
        ),
        if (hasPin)
          ListTile(
            leading: const Icon(Icons.lock_open, color: Colors.red),
            title: const Text('Clear PIN', style: TextStyle(color: Colors.red)),
            onTap: onClear,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Text(
            hasPin
                ? 'PIN protects entry to this editor.'
                : 'Optional. Set a PIN to require entry before opening this editor.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}
