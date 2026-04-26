//
//  pin_gate_screen.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/panel_store.dart';

// MARK: - State machine (testable)

/// PIN-gate verification state, separated from the view so it can be unit
/// tested without spinning up a UI. Tracks attempt count and lockout window.
class PinGateState {
  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 60);

  final PanelStore store;
  final DateTime Function() now;

  int attempts = 0;
  DateTime? lockedUntil;

  PinGateState({required this.store, DateTime Function()? now})
      : now = now ?? DateTime.now;

  bool get isLocked => lockedUntil != null && lockedUntil!.isAfter(now());

  int get lockoutSecondsRemaining {
    if (lockedUntil == null) return 0;
    final s = lockedUntil!.difference(now()).inSeconds;
    return s < 0 ? 0 : s;
  }

  Future<PinAttemptOutcome> attempt(String pin) async {
    if (isLocked) {
      return PinAttemptOutcome.lockedOut(lockoutSecondsRemaining);
    }
    if (await store.verifyPin(pin)) {
      attempts = 0;
      lockedUntil = null;
      return const PinAttemptOutcome.success();
    }
    attempts += 1;
    if (attempts >= maxAttempts) {
      lockedUntil = now().add(lockoutDuration);
      return PinAttemptOutcome.lockedOut(lockoutDuration.inSeconds);
    }
    return PinAttemptOutcome.wrong(maxAttempts - attempts);
  }
}

class PinAttemptOutcome {
  final _PinOutcomeKind kind;
  final int value;
  const PinAttemptOutcome.success()    : kind = _PinOutcomeKind.success, value = 0;
  const PinAttemptOutcome.wrong(this.value) : kind = _PinOutcomeKind.wrong;
  const PinAttemptOutcome.lockedOut(this.value) : kind = _PinOutcomeKind.lockedOut;

  bool get isSuccess => kind == _PinOutcomeKind.success;
  bool get isWrong => kind == _PinOutcomeKind.wrong;
  bool get isLockedOut => kind == _PinOutcomeKind.lockedOut;

  @override
  bool operator ==(Object other) =>
      other is PinAttemptOutcome && other.kind == kind && other.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
  @override
  String toString() => 'PinAttemptOutcome($kind, $value)';
}

enum _PinOutcomeKind { success, wrong, lockedOut }

// MARK: - Gate screen

class PinGateScreen extends StatefulWidget {
  const PinGateScreen({super.key});

  @override
  State<PinGateScreen> createState() => _PinGateScreenState();
}

class _PinGateScreenState extends State<PinGateScreen> {
  final PanelStore _store = PanelStore.shared;
  late final PinGateState _state = PinGateState(store: _store);
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  String _message = '';
  Color _messageColor = Colors.black54;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pinFocus.requestFocus());
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _onChanged() async {
    final digits = _pinController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.length > 4 ? digits.substring(0, 4) : digits;
    if (trimmed != _pinController.text) {
      _pinController.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }
    if (trimmed.length == 4) {
      final outcome = await _state.attempt(trimmed);
      if (!mounted) return;
      if (outcome.isSuccess) {
        Navigator.pop(context, true);
      } else if (outcome.isWrong) {
        setState(() {
          _message = 'Incorrect PIN. ${outcome.value} attempt${outcome.value == 1 ? "" : "s"} remaining.';
          _messageColor = Colors.red;
          _pinController.clear();
        });
      } else {
        _beginLockoutTicker();
      }
    } else {
      setState(() {});
    }
  }

  void _beginLockoutTicker() {
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_state.isLocked) {
        t.cancel();
        if (!mounted) return;
        setState(() {
          _message = '';
          _messageColor = Colors.black54;
          _pinController.clear();
        });
        _pinFocus.requestFocus();
      } else {
        if (!mounted) return;
        setState(() {
          _message = 'Too many attempts. Try again in ${_state.lockoutSecondsRemaining}s.';
          _messageColor = Colors.red;
        });
      }
    });
    setState(() {
      _message = 'Too many attempts. Try again in ${_state.lockoutSecondsRemaining}s.';
      _messageColor = Colors.red;
    });
  }

  Future<void> _showResetSheet() async {
    final hasQuestion = await _store.hasSecurityQuestion();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Reset PIN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (hasQuestion)
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Answer Security Question'),
                onTap: () { Navigator.pop(ctx); _promptSecurityAnswer(); },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
            if (!hasQuestion)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  'No security question was set. Reinstall the app to clear the PIN.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptSecurityAnswer() async {
    final question = await _store.securityQuestion() ?? 'Security question';
    final controller = TextEditingController();
    if (!mounted) return;
    final answer = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Security Question'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(question),
            const SizedBox(height: 12),
            TextField(controller: controller, autofocus: true,
                decoration: const InputDecoration(labelText: 'Your answer')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (answer == null) return;
    try {
      await _store.resetPinViaSecurityAnswer(answer);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PanelStoreException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("That's not the answer we have on file."),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filled = _pinController.text.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter PIN'),
        leading: TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        leadingWidth: 80,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: i < filled ? Colors.black : Colors.black12,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
            // Hidden text field that drives entry. Sized to 1x1 so it doesn't
            // visually compete with the dots above.
            SizedBox(
              width: 1, height: 1,
              child: TextField(
                controller: _pinController,
                focusNode: _pinFocus,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4)],
                style: const TextStyle(color: Colors.transparent),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            const SizedBox(height: 24),
            Text(_message, textAlign: TextAlign.center,
                style: TextStyle(color: _messageColor, fontSize: 13)),
            const SizedBox(height: 16),
            TextButton(onPressed: _showResetSheet, child: const Text('Forgot PIN?')),
          ],
        ),
      ),
    );
  }
}
