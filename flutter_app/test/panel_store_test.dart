//
//  panel_store_test.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iinteract/models/configuration_mode.dart';
import 'package:iinteract/models/panel.dart';
import 'package:iinteract/models/panel_loader.dart';
import 'package:iinteract/models/panel_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PanelStore store;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('PanelStoreTests-');
    store = PanelStore.shared;
    store.overrideDirectoryForTests(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('JSON round-trip', () {
    test('user panel persists and reloads', () async {
      final panel = Panel.user(
        title: 'School',
        color: const Color.fromRGBO(64, 128, 192, 1),
        interactions: [Interaction.user(id: 'i1', name: 'playground')],
      );
      await store.savePanel(panel);
      final reloaded = await store.userPanels();
      expect(reloaded, hasLength(1));
      expect(reloaded[0].title, 'School');
      expect(reloaded[0].interactions, hasLength(1));
      expect(reloaded[0].interactions[0].name, 'playground');
      expect(reloaded[0].isBuiltIn, isFalse);
    });
  });

  group('Layout', () {
    test('applyLayout filters hidden and orders the rest', () async {
      final p1 = Panel.user(title: 'Alpha', color: const Color(0xFF00FF00));
      final p2 = Panel.user(title: 'Beta',  color: const Color(0xFFFF0000));
      final p3 = Panel.user(title: 'Gamma', color: const Color(0xFF0000FF));
      await store.setHidden(true, p2.id);
      await store.setOrder([p3.id, p1.id]);
      final l = await store.layout();
      final result = store.applyLayout([p1, p2, p3], l);
      expect(result.map((p) => p.title).toList(), ['Gamma', 'Alpha']);
    });

    test('applyOrder alone keeps hidden panels', () async {
      final p1 = Panel.user(title: 'A', color: const Color(0xFF00FF00));
      final p2 = Panel.user(title: 'B', color: const Color(0xFFFF0000));
      await store.setHidden(true, p1.id);
      await store.setOrder([p2.id, p1.id]);
      final l = await store.layout();
      expect(store.applyOrder([p1, p2], l).map((p) => p.title).toList(), ['B', 'A']);
    });
  });

  group('Validators', () {
    test('rejects empty + built-in collisions (case-insensitive)', () async {
      expect(await store.isNameAvailable(''), isFalse);
      expect(await store.isNameAvailable('I feel'), isFalse);
      expect(await store.isNameAvailable('i feel'), isFalse);
      expect(await store.isNameAvailable(' I feel '), isFalse);
      expect(await store.isNameAvailable('School'), isTrue);
    });

    test('savePanel enforces uniqueness', () async {
      await store.savePanel(Panel.user(title: 'Foo', color: const Color(0xFFFF0000)));
      expect(
        () => store.savePanel(Panel.user(title: 'Foo', color: const Color(0xFF00FF00))),
        throwsA(isA<PanelStoreException>()
            .having((e) => e.code, 'code', PanelStoreError.nameNotUnique)),
      );
    });

    test('savePanel rejects > 6 interactions', () async {
      final tooMany = List.generate(7, (i) => Interaction.user(id: 'i$i', name: 'x$i'));
      expect(
        () => store.savePanel(Panel.user(
          title: 'TooMany',
          color: const Color(0xFFFF0000),
          interactions: tooMany,
        )),
        throwsA(isA<PanelStoreException>()
            .having((e) => e.code, 'code', PanelStoreError.capacityExceeded)),
      );
    });

    test('savePanel allows rename via excluding-self', () async {
      final p = Panel.user(title: 'Original', color: const Color(0xFFFF0000));
      await store.savePanel(p);
      p.title = 'Renamed';
      await store.savePanel(p);
      final list = await store.userPanels();
      expect(list, hasLength(1));
      expect(list.first.title, 'Renamed');
    });
  });

  group('PIN', () {
    test('set + verify + clear', () async {
      expect(await store.hasPin(), isFalse);
      await store.setPin('1234');
      expect(await store.hasPin(), isTrue);
      expect(await store.verifyPin('1234'), isTrue);
      expect(await store.verifyPin('0000'), isFalse);
      await store.clearPin();
      expect(await store.hasPin(), isFalse);
    });

    test('reset via security answer (case + whitespace insensitive)', () async {
      await store.setPin('1234', question: 'Pet?', answer: 'Fido');
      await store.resetPinViaSecurityAnswer('  fido  ');
      expect(await store.hasPin(), isFalse);
    });

    test('reset via security answer fails on wrong answer', () async {
      await store.setPin('1234', question: 'Pet?', answer: 'Fido');
      expect(
        () => store.resetPinViaSecurityAnswer('Spot'),
        throwsA(isA<PanelStoreException>()
            .having((e) => e.code, 'code', PanelStoreError.incorrectAnswer)),
      );
      expect(await store.hasPin(), isTrue);
    });

    test('reset via security answer fails when no question set', () async {
      await store.setPin('1234');
      expect(
        () => store.resetPinViaSecurityAnswer('anything'),
        throwsA(isA<PanelStoreException>()
            .having((e) => e.code, 'code', PanelStoreError.noSecurityQuestionSet)),
      );
    });
  });

  group('loadPanels()', () {
    test('default mode returns built-ins verbatim', () async {
      await ConfigurationMode.set(ConfigurationMode.defaultMode);
      final loaded = await loadPanels(store: store);
      expect(loaded.map((p) => p.title).toList(),
          builtInPanels().map((p) => p.title).toList());
      expect(loaded.every((p) => p.isBuiltIn), isTrue);
    });

    test('custom mode with empty store returns built-ins', () async {
      final loaded = await loadPanels(mode: ConfigurationMode.custom, store: store);
      expect(loaded.map((p) => p.title).toList(),
          builtInPanels().map((p) => p.title).toList());
    });

    test('custom mode merges user panels after built-ins', () async {
      final user = Panel.user(title: 'School', color: const Color(0xFF00CCAA));
      await store.savePanel(user);
      final loaded = await loadPanels(mode: ConfigurationMode.custom, store: store);
      expect(loaded.last.title, 'School');
      expect(loaded.length, builtInPanels().length + 1);
    });

    test('custom mode applies hidden + order', () async {
      final builtIns = builtInPanels();
      await store.setHidden(true, builtIns.first.id);
      await store.setOrder([builtIns[1].id]);
      final loaded = await loadPanels(mode: ConfigurationMode.custom, store: store);
      expect(loaded.any((p) => p.id == builtIns.first.id), isFalse);
      expect(loaded.first.id, builtIns[1].id);
    });
  });

  group('Hydration', () {
    test('no-op for built-in interactions', () async {
      final i = Interaction.builtIn('happy');
      final beforePic = i.picturePath;
      final beforeBoy = i.boySoundPath;
      await store.hydrate(Panel(
        id: 'tmp', title: 'tmp', color: const Color(0xFF000000),
        interactions: [i], isBuiltIn: false,
      ));
      // Hydrate skips built-ins entirely.
      expect(i.picturePath, beforePic);
      expect(i.boySoundPath, beforeBoy);
    });

    test('user interaction picks up files when present', () async {
      final i = Interaction.user(id: 'iid', name: 'playground');
      // Write a real JPEG-ish blob and stub audio files at the expected paths.
      await store.saveInteractionPicture(Uint8List.fromList(List.filled(8, 0xFF)), i.id);
      final boy = await store.audioPath(i.id, Voice.boy);
      final girl = await store.audioPath(i.id, Voice.girl);
      await File(boy).writeAsBytes([0]);
      await File(girl).writeAsBytes([0]);

      await store.hydrate(Panel(
        id: 'p', title: 'p', color: const Color(0xFF000000),
        interactions: [i], isBuiltIn: false,
      ));
      expect(i.picturePath, await store.picturePath(i.id));
      expect(i.boySoundPath, boy);
      expect(i.girlSoundPath, girl);
    });

    test('deleteInteractionAssets removes all three files', () async {
      const id = 'cleanup-id';
      await store.saveInteractionPicture(Uint8List.fromList([1]), id);
      await File(await store.audioPath(id, Voice.boy)).writeAsBytes([0]);
      await File(await store.audioPath(id, Voice.girl)).writeAsBytes([0]);
      await store.deleteInteractionAssets(id);
      expect(await File(await store.picturePath(id)).exists(), isFalse);
      expect(await File(await store.audioPath(id, Voice.boy)).exists(), isFalse);
      expect(await File(await store.audioPath(id, Voice.girl)).exists(), isFalse);
    });
  });

  group('Stable IDs', () {
    test('built-ins are deterministic', () {
      expect(stableIdFor('I feel'), stableIdFor('I feel'));
      expect(stableIdFor('I feel'), isNot(stableIdFor('I need')));
    });
  });
}
