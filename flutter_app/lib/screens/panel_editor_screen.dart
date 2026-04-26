//
//  panel_editor_screen.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/panel.dart';
import '../models/panel_store.dart';
import 'interaction_editor_screen.dart';
import 'panel_detail_screen.dart' show interactionImage;

/// Edits a single user-authored panel: title, color, interaction list.
/// Validates the title against PanelStore.isNameAvailable in real-time
/// (case-insensitive across built-ins + other user panels) and disables Save
/// until the title is valid. Add Interaction is hidden when at the 6-cap.
class PanelEditorScreen extends StatefulWidget {
  /// Pass null for "new"; pass an existing panel to edit it (a clone is made
  /// so Cancel doesn't leak in-memory mutations).
  final Panel? existing;
  const PanelEditorScreen({super.key, this.existing});

  @override
  State<PanelEditorScreen> createState() => _PanelEditorScreenState();
}

class _PanelEditorScreenState extends State<PanelEditorScreen> {
  final PanelStore _store = PanelStore.shared;
  final TextEditingController _titleController = TextEditingController();
  late Panel _working;
  String? _titleError;
  bool _saveEnabled = false;

  @override
  void initState() {
    super.initState();
    final orig = widget.existing;
    if (orig != null) {
      _working = Panel(
        id: orig.id,
        title: orig.title,
        color: orig.color,
        interactions: List.of(orig.interactions),
        isBuiltIn: false,
      );
    } else {
      _working = Panel.user(title: '', color: const Color(0xFF42A5F5));
    }
    _titleController.text = _working.title;
    _titleController.addListener(_onTitleChanged);
    _revalidate();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    _working.title = _titleController.text;
    _revalidate();
  }

  Future<void> _revalidate() async {
    final trimmed = _working.title.trim();
    final ok = trimmed.isNotEmpty &&
        await _store.isNameAvailable(trimmed, excluding: _working.id);
    if (!mounted) return;
    setState(() {
      _saveEnabled = ok;
      _titleError = (trimmed.isNotEmpty && !ok) ? 'That name is already in use.' : null;
    });
  }

  Future<void> _save() async {
    try {
      await _store.savePanel(_working);
      if (!mounted) return;
      Navigator.pop(context, _working);
    } on PanelStoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _titleError = e.code == PanelStoreError.nameNotUnique
            ? 'That name is already in use.'
            : 'Could not save: ${e.code.name}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _pickColor() async {
    Color picked = _working.color;
    final result = await showDialog<Color?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _working.color,
            enableAlpha: false,
            labelTypes: const [],
            onColorChanged: (c) => picked = c,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, picked), child: const Text('Use')),
        ],
      ),
    );
    if (result != null) setState(() => _working.color = result);
  }

  Future<void> _addInteraction() async {
    final created = await Navigator.push<Interaction?>(
      context,
      MaterialPageRoute(builder: (_) => const InteractionEditorScreen()),
    );
    if (created != null) {
      setState(() => _working.interactions.add(created));
    }
  }

  Future<void> _editInteraction(int index) async {
    final updated = await Navigator.push<Interaction?>(
      context,
      MaterialPageRoute(
        builder: (_) => InteractionEditorScreen(existing: _working.interactions[index]),
      ),
    );
    if (updated != null) {
      setState(() => _working.interactions[index] = updated);
    }
  }

  void _deleteInteraction(int index) {
    final removed = _working.interactions.removeAt(index);
    // Best-effort cleanup of the user's recorded blobs.
    if (!removed.isBuiltIn) _store.deleteInteractionAssets(removed.id);
    setState(() {});
  }

  void _reorderInteractions(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final i = _working.interactions.removeAt(oldIndex);
    _working.interactions.insert(newIndex, i);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final atCap = _working.interactions.length >= PanelStore.maxInteractionsPerUserPanel;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New Panel' : 'Edit Panel'),
        actions: [
          TextButton(
            onPressed: _saveEnabled ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        children: [
          const _SectionHeader('TITLE'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Panel name',
                errorText: _titleError,
              ),
            ),
          ),
          const _SectionHeader('COLOR'),
          ListTile(
            title: const Text('Color'),
            onTap: _pickColor,
            trailing: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _working.color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
            ),
          ),
          _SectionHeader('INTERACTIONS  (${_working.interactions.length}/${PanelStore.maxInteractionsPerUserPanel})'),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _working.interactions.length,
            onReorder: _reorderInteractions,
            itemBuilder: (ctx, i) {
              final interaction = _working.interactions[i];
              return ListTile(
                key: ValueKey('${interaction.id}-$i'),
                leading: SizedBox(
                  width: 44, height: 44,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: interactionImage(interaction),
                  ),
                ),
                title: Text(interaction.name),
                onTap: () => _editInteraction(i),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteInteraction(i),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                  ],
                ),
              );
            },
          ),
          if (!atCap)
            ListTile(
              leading: const Icon(Icons.add_circle, color: Colors.blue),
              title: const Text('Add Interaction'),
              onTap: _addInteraction,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              atCap
                  ? "You've reached the 6-item maximum."
                  : 'Up to 6 items per page.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
    );
  }
}
