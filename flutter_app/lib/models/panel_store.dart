//
//  panel_store.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'panel.dart';

/// Single source of truth for user-authored panel data on the Flutter side.
/// Mirrors the native iOS PanelStore: persistence + layout (visibility +
/// order) + uniqueness/capacity validators + PIN with two reset paths.
///
/// Differences from the iOS version:
///   * No iCloud KVS sync (no first-class Flutter equivalent in v3.0).
///   * No "iCloud account presence" reset path; instead, PIN-reset falls back
///     to security-question only (or wipe via "delete app").
class PanelStore {
  PanelStore._();
  static final PanelStore shared = PanelStore._();

  static const int maxInteractionsPerUserPanel = 6;

  static const _kvsPanelsKey = 'panelstore.panels';
  static const _kvsLayoutKey = 'panelstore.layout';
  static const _kvsPinHashKey = 'panelstore.pin_hash';
  static const _kvsPinQuestionKey = 'panelstore.pin_question';
  static const _kvsPinAnswerHashKey = 'panelstore.pin_answer_hash';

  /// Override-able for tests; in production resolves to the platform's
  /// Application Documents directory.
  Directory? _baseDir;

  Future<Directory> get _directory async {
    if (_baseDir != null) return _baseDir!;
    final app = await getApplicationDocumentsDirectory();
    final dir = Directory('${app.path}/PanelStore');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get assetsDirectory async {
    final dir = Directory('${(await _directory).path}/UserAssets');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Per-edit asset URLs keyed by interaction id.
  Future<String> picturePath(String interactionId) async =>
      '${(await assetsDirectory).path}/$interactionId.jpg';
  Future<String> audioPath(String interactionId, Voice voice) async =>
      '${(await assetsDirectory).path}/$interactionId.${voice.name}.m4a';

  // MARK: - User panels (persisted as JSON)

  Future<List<Panel>> userPanels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kvsPanelsKey);
    if (raw == null) return [];
    try {
      final decoded = json.decode(raw) as List;
      return decoded
          .map((j) => Panel.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveUserPanels(List<Panel> panels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kvsPanelsKey, json.encode(panels.map((p) => p.toJson()).toList()));
  }

  Future<void> savePanel(Panel panel) async {
    if (panel.isBuiltIn) return;
    if (!await isNameAvailable(panel.title, excluding: panel.id)) {
      throw const PanelStoreException(PanelStoreError.nameNotUnique);
    }
    if (panel.interactions.length > maxInteractionsPerUserPanel) {
      throw const PanelStoreException(PanelStoreError.capacityExceeded);
    }
    final list = await userPanels();
    final i = list.indexWhere((p) => p.id == panel.id);
    if (i >= 0) {
      list[i] = panel;
    } else {
      list.add(panel);
    }
    await _saveUserPanels(list);
  }

  Future<void> deletePanel(String id) async {
    final list = await userPanels();
    list.removeWhere((p) => p.id == id);
    await _saveUserPanels(list);
  }

  // MARK: - Layout (visibility + order, applies to built-ins AND user panels)

  Future<Layout> layout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kvsLayoutKey);
    if (raw == null) return Layout.empty();
    try {
      return Layout.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Layout.empty();
    }
  }

  Future<void> _saveLayout(Layout l) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kvsLayoutKey, json.encode(l.toJson()));
  }

  Future<void> setHidden(bool hidden, String panelId) async {
    final l = await layout();
    final updated = Set<String>.from(l.hiddenIds);
    if (hidden) {
      updated.add(panelId);
    } else {
      updated.remove(panelId);
    }
    await _saveLayout(Layout(hiddenIds: updated, orderedIds: l.orderedIds));
  }

  Future<void> setOrder(List<String> ids) async {
    final l = await layout();
    await _saveLayout(Layout(hiddenIds: l.hiddenIds, orderedIds: ids));
  }

  /// Returns `panels` ordered by saved layout. Panels not in `orderedIds`
  /// keep their original relative position at the end.
  List<Panel> applyOrder(List<Panel> panels, Layout l) {
    if (l.orderedIds.isEmpty) return panels;
    final byId = {for (final p in panels) p.id: p};
    final ordered = l.orderedIds.map((id) => byId[id]).whereType<Panel>().toList();
    final unordered = panels.where((p) => !l.orderedIds.contains(p.id)).toList();
    return [...ordered, ...unordered];
  }

  /// Filters hidden panels out.
  List<Panel> applyHiddenFilter(List<Panel> panels, Layout l) {
    return panels.where((p) => !l.hiddenIds.contains(p.id)).toList();
  }

  /// Filter then order — used by the main list. The editor uses applyOrder
  /// directly so it can show hidden panels for un-hiding.
  List<Panel> applyLayout(List<Panel> panels, Layout l) {
    return applyOrder(applyHiddenFilter(panels, l), l);
  }

  // MARK: - Validators

  Future<bool> isNameAvailable(String name, {String? excluding}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final needle = trimmed.toLowerCase();
    for (final p in builtInPanels()) {
      if (p.title.toLowerCase() == needle) return false;
    }
    for (final p in await userPanels()) {
      if (p.id != excluding && p.title.toLowerCase() == needle) return false;
    }
    return true;
  }

  Future<bool> canAddInteraction(String panelId) async {
    final p = (await userPanels()).firstWhere(
      (p) => p.id == panelId,
      orElse: () => Panel.user(title: '', color: const Color(0xFF000000)),
    );
    if (p.title.isEmpty) return false;
    return p.interactions.length < maxInteractionsPerUserPanel;
  }

  // MARK: - Hydration (reattach picture / audio file paths to a user panel)

  Future<void> hydrate(Panel panel) async {
    if (panel.isBuiltIn) return;
    for (final i in panel.interactions) {
      if (i.isBuiltIn) continue;
      final pic = await picturePath(i.id);
      if (await File(pic).exists()) i.picturePath = pic;
      final boy = await audioPath(i.id, Voice.boy);
      if (await File(boy).exists()) i.boySoundPath = boy;
      final girl = await audioPath(i.id, Voice.girl);
      if (await File(girl).exists()) i.girlSoundPath = girl;
    }
  }

  // MARK: - Asset writes

  Future<void> saveInteractionPicture(Uint8List jpegBytes, String interactionId) async {
    final path = await picturePath(interactionId);
    await File(path).writeAsBytes(jpegBytes, flush: true);
  }

  Future<void> deleteInteractionAssets(String interactionId) async {
    await deleteFileIfExists(await picturePath(interactionId));
    await deleteFileIfExists(await audioPath(interactionId, Voice.boy));
    await deleteFileIfExists(await audioPath(interactionId, Voice.girl));
  }

  // MARK: - PIN + security question

  Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kvsPinHashKey) != null;
  }

  Future<String?> securityQuestion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kvsPinQuestionKey);
  }

  Future<bool> hasSecurityQuestion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kvsPinQuestionKey) != null &&
        prefs.getString(_kvsPinAnswerHashKey) != null;
  }

  Future<void> setPin(String pin, {String? question, String? answer}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kvsPinHashKey, _hash(pin));
    final q = question?.trim() ?? '';
    final a = answer?.trim() ?? '';
    if (q.isNotEmpty && a.isNotEmpty) {
      await prefs.setString(_kvsPinQuestionKey, q);
      await prefs.setString(_kvsPinAnswerHashKey, _hash(a.toLowerCase()));
    } else {
      await prefs.remove(_kvsPinQuestionKey);
      await prefs.remove(_kvsPinAnswerHashKey);
    }
  }

  Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kvsPinHashKey);
    await prefs.remove(_kvsPinQuestionKey);
    await prefs.remove(_kvsPinAnswerHashKey);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kvsPinHashKey);
    if (stored == null) return false;
    return _hash(pin) == stored;
  }

  Future<void> resetPinViaSecurityAnswer(String answer) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kvsPinAnswerHashKey);
    if (stored == null) {
      throw const PanelStoreException(PanelStoreError.noSecurityQuestionSet);
    }
    if (_hash(answer.trim().toLowerCase()) != stored) {
      throw const PanelStoreException(PanelStoreError.incorrectAnswer);
    }
    await clearPin();
  }

  // MARK: - Test seam

  @visibleForTesting
  void overrideDirectoryForTests(Directory dir) {
    _baseDir = dir;
  }

  static String _hash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}

class Layout {
  final Set<String> hiddenIds;
  final List<String> orderedIds;

  const Layout({required this.hiddenIds, required this.orderedIds});
  factory Layout.empty() => const Layout(hiddenIds: {}, orderedIds: []);

  Map<String, dynamic> toJson() => {
        'hiddenIds': hiddenIds.toList(),
        'orderedIds': orderedIds,
      };

  factory Layout.fromJson(Map<String, dynamic> json) {
    return Layout(
      hiddenIds: ((json['hiddenIds'] as List?) ?? const []).cast<String>().toSet(),
      orderedIds: ((json['orderedIds'] as List?) ?? const []).cast<String>(),
    );
  }
}

enum Voice { boy, girl }

enum PanelStoreError {
  nameNotUnique,
  capacityExceeded,
  panelNotFound,
  noSecurityQuestionSet,
  incorrectAnswer,
  assetWriteFailed,
}

class PanelStoreException implements Exception {
  final PanelStoreError code;
  const PanelStoreException(this.code);
  @override
  String toString() => 'PanelStoreException(${code.name})';
}
