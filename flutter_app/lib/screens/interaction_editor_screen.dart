//
//  interaction_editor_screen.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/panel.dart';
import '../models/panel_store.dart';

/// Edits one user-authored interaction: name, picture, boy + girl voices.
/// New picks/recordings land in a per-edit temp directory and only copy over
/// to PanelStore's asset paths on Save, so Cancel cleanly discards everything.
class InteractionEditorScreen extends StatefulWidget {
  final Interaction? existing;
  const InteractionEditorScreen({super.key, this.existing});

  @override
  State<InteractionEditorScreen> createState() => _InteractionEditorScreenState();
}

class _InteractionEditorScreenState extends State<InteractionEditorScreen> {
  final PanelStore _store = PanelStore.shared;
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();
  final TextEditingController _nameController = TextEditingController();

  late String _workingId;
  String _workingName = '';
  String? _workingPictureFilePath;        // temp file (this edit) or hydrated existing
  String? _workingBoyAudioPath;           // temp file or existing
  String? _workingGirlAudioPath;
  Voice? _currentlyRecording;             // null when not recording
  Directory? _tempDir;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final tmpRoot = await getTemporaryDirectory();
    _tempDir = await Directory('${tmpRoot.path}/InteractionEditor-${DateTime.now().microsecondsSinceEpoch}')
        .create(recursive: true);

    final orig = widget.existing;
    if (orig != null) {
      _workingId = orig.id;
      _workingName = orig.name;
      _nameController.text = orig.name;
      _workingPictureFilePath = orig.pictureIsFile ? orig.picturePath : null;
      _workingBoyAudioPath = orig.boySoundIsFile ? orig.boySoundPath : null;
      _workingGirlAudioPath = orig.girlSoundIsFile ? orig.girlSoundPath : null;
    } else {
      _workingId = stableIdFor('user-${DateTime.now().microsecondsSinceEpoch}');
    }
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _previewPlayer.stop();
    _previewPlayer.dispose();
    _recorder.dispose();
    _nameController.dispose();
    if (_tempDir != null) {
      _tempDir!.delete(recursive: true).catchError((_) => _tempDir!);
    }
    super.dispose();
  }

  bool get _canSave => _workingName.trim().isNotEmpty && _workingPictureFilePath != null;

  Future<void> _cancel() async {
    await _previewPlayer.stop();
    if (!mounted) return;
    Navigator.pop(context, null);
  }

  Future<void> _save() async {
    await _previewPlayer.stop();
    try {
      // Picture: copy temp to PanelStore asset path.
      if (_workingPictureFilePath != null) {
        final dest = await _store.picturePath(_workingId);
        if (_workingPictureFilePath != dest) {
          final bytes = await File(_workingPictureFilePath!).readAsBytes();
          await _store.saveInteractionPicture(bytes, _workingId);
        }
      }
      // Audio: same pattern for each voice.
      if (_workingBoyAudioPath != null) {
        final dest = await _store.audioPath(_workingId, Voice.boy);
        if (_workingBoyAudioPath != dest) {
          await File(_workingBoyAudioPath!).copy(dest);
        }
      }
      if (_workingGirlAudioPath != null) {
        final dest = await _store.audioPath(_workingId, Voice.girl);
        if (_workingGirlAudioPath != dest) {
          await File(_workingGirlAudioPath!).copy(dest);
        }
      }
      final interaction = Interaction.user(id: _workingId, name: _workingName.trim());
      await _store.hydrate(Panel(
        id: 'tmp', title: 'tmp', color: const Color(0xFF000000),
        interactions: [interaction], isBuiltIn: false,
      ));
      if (!mounted) return;
      Navigator.pop(context, interaction);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _pickPicture() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (picked == null) return;
    // Copy into our temp dir so the picker file doesn't disappear.
    final temp = '${_tempDir!.path}/picture.jpg';
    await File(picked.path).copy(temp);
    setState(() => _workingPictureFilePath = temp);
  }

  Future<void> _toggleRecord(Voice voice) async {
    if (_currentlyRecording == voice) {
      // Stop
      final path = await _recorder.stop();
      if (path != null) {
        setState(() {
          if (voice == Voice.boy) {
            _workingBoyAudioPath = path;
          } else {
            _workingGirlAudioPath = path;
          }
          _currentlyRecording = null;
        });
      } else {
        setState(() => _currentlyRecording = null);
      }
      return;
    }
    // Start
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Microphone permission denied. Enable it in Settings.'),
      ));
      return;
    }
    final dest = '${_tempDir!.path}/${voice.name}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, numChannels: 1),
      path: dest,
    );
    setState(() => _currentlyRecording = voice);
  }

  Future<void> _previewAudio(Voice voice) async {
    final path = voice == Voice.boy ? _workingBoyAudioPath : _workingGirlAudioPath;
    if (path == null) return;
    await _previewPlayer.stop();
    await _previewPlayer.play(DeviceFileSource(path));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New Interaction' : 'Edit Interaction'),
        leading: TextButton(onPressed: _cancel, child: const Text('Cancel')),
        leadingWidth: 80,
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        children: [
          const _SectionHeader('NAME'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'happy, snack, hello…'),
              onChanged: (v) => setState(() => _workingName = v),
            ),
          ),
          const _SectionHeader('PICTURE'),
          ListTile(
            leading: _workingPictureFilePath == null
                ? const Icon(Icons.add_photo_alternate, size: 44, color: Colors.blue)
                : SizedBox(
                    width: 44, height: 44,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(_workingPictureFilePath!), fit: BoxFit.cover),
                    ),
                  ),
            title: Text(_workingPictureFilePath == null ? 'Choose Picture…' : 'Change Picture…'),
            onTap: _pickPicture,
            trailing: const Icon(Icons.chevron_right),
          ),
          const _SectionHeader('VOICES'),
          _voiceRow(Voice.boy,  'Boy voice'),
          _voiceRow(Voice.girl, 'Girl voice'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              'Record a boy and a girl voice. Either one is required.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceRow(Voice voice, String label) {
    final isRecording = _currentlyRecording == voice;
    final hasAudio = (voice == Voice.boy ? _workingBoyAudioPath : _workingGirlAudioPath) != null;
    return ListTile(
      title: Text(label),
      subtitle: Text(isRecording ? 'Recording…' : (hasAudio ? 'Recorded ✓' : 'Not recorded')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAudio && !isRecording)
            IconButton(
              icon: const Icon(Icons.play_circle, color: Colors.blue),
              onPressed: () => _previewAudio(voice),
            ),
          IconButton(
            icon: Icon(
              isRecording ? Icons.stop_circle : Icons.mic,
              color: isRecording ? Colors.red : Colors.blue,
            ),
            onPressed: () => _toggleRecord(voice),
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
