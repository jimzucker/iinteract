//
//  pin_gate_state_test.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:iinteract/models/panel_store.dart';
import 'package:iinteract/screens/pin_gate_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PanelStore store;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('PinGateStateTests-');
    store = PanelStore.shared;
    store.overrideDirectoryForTests(tempDir);
    await store.setPin('1234');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await store.clearPin();
  });

  test('correct PIN returns success', () async {
    final state = PinGateState(store: store);
    final outcome = await state.attempt('1234');
    expect(outcome.isSuccess, isTrue);
  });

  test('wrong PIN returns remainingAttempts', () async {
    final state = PinGateState(store: store);
    final outcome = await state.attempt('0000');
    expect(outcome.isWrong, isTrue);
    expect(outcome.value, PinGateState.maxAttempts - 1);
  });

  test('5 wrong attempts lock out', () async {
    final state = PinGateState(store: store);
    PinAttemptOutcome? last;
    for (var i = 0; i < PinGateState.maxAttempts; i++) {
      last = await state.attempt('0000');
    }
    expect(last!.isLockedOut, isTrue);
    expect(state.isLocked, isTrue);
  });

  test('correct PIN during lockout still returns lockedOut', () async {
    final state = PinGateState(store: store);
    for (var i = 0; i < PinGateState.maxAttempts; i++) {
      await state.attempt('0000');
    }
    final outcome = await state.attempt('1234');
    expect(outcome.isLockedOut, isTrue);
  });

  test('lockout expires after duration', () async {
    var fakeNow = DateTime(2026);
    final state = PinGateState(store: store, now: () => fakeNow);
    for (var i = 0; i < PinGateState.maxAttempts; i++) {
      await state.attempt('0000');
    }
    expect(state.isLocked, isTrue);
    fakeNow = fakeNow.add(PinGateState.lockoutDuration + const Duration(seconds: 1));
    expect(state.isLocked, isFalse);
    final outcome = await state.attempt('1234');
    expect(outcome.isSuccess, isTrue);
  });

  test('success resets attempts', () async {
    final state = PinGateState(store: store);
    await state.attempt('0000');
    await state.attempt('0000');
    expect(state.attempts, 2);
    await state.attempt('1234');
    expect(state.attempts, 0);
  });
}
