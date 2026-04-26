//
//  pin_setup_screen.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/panel_store.dart';

/// Set / change the PIN, with an optional security question. Reachable from
/// the Security section in PanelListEditor. The user is already past the
/// gate (or no PIN is set yet), so we don't re-verify the existing PIN here.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final PanelStore _store = PanelStore.shared;
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _question = TextEditingController();
  final TextEditingController _answer = TextEditingController();
  bool _hasPin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    for (final c in [_new, _confirm, _question, _answer]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _bootstrap() async {
    final hasPin = await _store.hasPin();
    final question = await _store.securityQuestion() ?? '';
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _question.text = question;
    });
  }

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  bool get _pinValid => _new.text.length == 4 && _new.text == _confirm.text;
  bool get _qValid {
    final q = _question.text.trim();
    final a = _answer.text.trim();
    return (q.isEmpty && a.isEmpty) || (q.isNotEmpty && a.isNotEmpty);
  }

  String? get _errorMessage {
    if (_new.text.isNotEmpty && _new.text.length != 4) return 'PIN must be 4 digits.';
    if (_new.text.length == 4 && _confirm.text.isNotEmpty && _new.text != _confirm.text) {
      return "PINs don't match.";
    }
    if (!_qValid) return 'Set both a question and an answer, or neither.';
    return null;
  }

  bool get _canSave => _pinValid && _qValid;

  Future<void> _save() async {
    final q = _question.text.trim();
    final a = _answer.text.trim();
    await _store.setPin(_new.text, question: q.isEmpty ? null : q, answer: a.isEmpty ? null : a);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_hasPin ? 'Change PIN' : 'Set PIN'),
        leading: TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        leadingWidth: 80,
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('PIN'),
          TextField(
            controller: _new,
            decoration: const InputDecoration(labelText: 'New PIN (4 digits)'),
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4)],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            decoration: InputDecoration(labelText: 'Confirm PIN', errorText: _errorMessage),
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4)],
          ),
          const SizedBox(height: 24),
          const _SectionHeader('SECURITY QUESTION (OPTIONAL)'),
          TextField(
            controller: _question,
            decoration: const InputDecoration(
              labelText: 'Question (e.g. Mother\'s maiden name)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            decoration: const InputDecoration(labelText: 'Answer'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Lets you reset your PIN later if you forget it.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
    );
  }
}
