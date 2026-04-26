//
//  panel.dart
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
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';

/// Stable id derived from a string (used by built-ins so the same panel
/// always has the same id across launches and devices). SHA-256 of the
/// utf8 bytes, formatted as 32 lowercase hex chars.
String stableIdFor(String input) {
  final bytes = utf8.encode(input);
  return sha256.convert(bytes).toString();
}

class Interaction {
  final String id;
  String name;
  final bool isBuiltIn;

  /// Picture: bundled (built-ins use 'assets/images/<name>.jpg') or a file
  /// path under Application Documents (user interactions, after editor save).
  String? picturePath;

  /// Audio paths follow the same pattern. Built-ins point at bundled
  /// assets/sounds/<voice>_<name>.mp3; user interactions point at files
  /// recorded by the InteractionEditor.
  String? boySoundPath;
  String? girlSoundPath;

  Interaction.builtIn(String name)
      : id = stableIdFor(name),
        name = name,
        isBuiltIn = true,
        picturePath = 'assets/images/$name.jpg',
        boySoundPath = 'assets/sounds/boy_$name.mp3',
        girlSoundPath = 'assets/sounds/girl_$name.mp3';

  Interaction.user({required this.id, required this.name})
      : isBuiltIn = false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isBuiltIn': isBuiltIn,
      };

  factory Interaction.fromJson(Map<String, dynamic> json) {
    final isBuiltIn = (json['isBuiltIn'] as bool?) ?? false;
    final name = json['name'] as String;
    if (isBuiltIn) return Interaction.builtIn(name);
    return Interaction.user(id: json['id'] as String, name: name);
  }

  /// True when the picture/audio path points to a real on-disk file (user
  /// interactions). False for built-ins (which use Flutter's asset bundle).
  bool get pictureIsFile => picturePath != null && !picturePath!.startsWith('assets/');
  bool get boySoundIsFile => boySoundPath != null && !boySoundPath!.startsWith('assets/');
  bool get girlSoundIsFile => girlSoundPath != null && !girlSoundPath!.startsWith('assets/');
}

class Panel {
  final String id;
  String title;
  Color color;
  List<Interaction> interactions;
  final bool isBuiltIn;

  Panel({
    required this.id,
    required this.title,
    required this.color,
    required this.interactions,
    required this.isBuiltIn,
  });

  factory Panel.user({
    String? id,
    required String title,
    required Color color,
    List<Interaction>? interactions,
  }) {
    return Panel(
      id: id ?? stableIdFor('user-${DateTime.now().microsecondsSinceEpoch}-$title'),
      title: title,
      color: color,
      interactions: interactions ?? [],
      isBuiltIn: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'color': {
          'r': color.r,
          'g': color.g,
          'b': color.b,
          'a': color.a,
        },
        'isBuiltIn': isBuiltIn,
        'interactions': interactions.map((i) => i.toJson()).toList(),
      };

  factory Panel.fromJson(Map<String, dynamic> json) {
    final c = json['color'] as Map<String, dynamic>;
    return Panel(
      id: json['id'] as String,
      title: json['title'] as String,
      color: Color.fromRGBO(
        ((c['r'] as num).toDouble() * 255).round(),
        ((c['g'] as num).toDouble() * 255).round(),
        ((c['b'] as num).toDouble() * 255).round(),
        (c['a'] as num).toDouble(),
      ),
      isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
      interactions: (json['interactions'] as List)
          .map((i) => Interaction.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// The seven built-in panels. Same titles, colors, and interaction names as
/// the native iOS app's panels.plist so the two apps stay in lockstep.
List<Panel> builtInPanels() => [
      Panel(
        id: stableIdFor('I feel'),
        title: 'I feel',
        color: const Color.fromRGBO(87, 192, 255, 1),
        isBuiltIn: true,
        interactions: ['happy', 'sad', 'angry'].map(Interaction.builtIn).toList(),
      ),
      Panel(
        id: stableIdFor('I need'),
        title: 'I need',
        color: const Color.fromRGBO(255, 255, 83, 1),
        isBuiltIn: true,
        interactions: ['drink', 'eat', 'bathroom', 'break'].map(Interaction.builtIn).toList(),
      ),
      Panel(
        id: stableIdFor('I want to'),
        title: 'I want to',
        color: const Color.fromRGBO(253, 135, 39, 1),
        isBuiltIn: true,
        interactions: ['tv', 'play', 'book', 'computer'].map(Interaction.builtIn).toList(),
      ),
      Panel(
        id: stableIdFor('I need help'),
        title: 'I need help',
        color: const Color.fromRGBO(251, 0, 6, 1),
        isBuiltIn: true,
        interactions: ['headache', 'stomach', 'cut'].map(Interaction.builtIn).toList(),
      ),
      Panel(
        id: stableIdFor('Food'),
        title: 'Food',
        color: const Color.fromRGBO(18, 136, 67, 1),
        isBuiltIn: true,
        interactions: ['breakfast', 'lunch', 'dinner', 'dessert'].map(Interaction.builtIn).toList(),
      ),
      Panel(
        id: stableIdFor('Drink'),
        title: 'Drink',
        color: const Color.fromRGBO(42, 130, 255, 1),
        isBuiltIn: true,
        interactions: ['milk', 'water', 'juice', 'soda'].map(Interaction.builtIn).toList(),
      ),
      Panel(
        id: stableIdFor('Snacks'),
        title: 'Snacks',
        color: const Color.fromRGBO(88, 197, 84, 1),
        isBuiltIn: true,
        interactions: ['chips', 'cookie', 'pretzel', 'fruit'].map(Interaction.builtIn).toList(),
      ),
    ];

/// Back-compat alias for the screens that referenced the old top-level `panels`.
@Deprecated('Use builtInPanels() or PanelStore.load(mode:) instead')
List<Panel> get panels => builtInPanels();

/// Helper for tests/debug to delete a real on-disk asset file safely.
Future<void> deleteFileIfExists(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
