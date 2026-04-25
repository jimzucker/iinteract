//
//  main.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:flutter/material.dart';
import 'screens/panel_list_screen.dart';

void main() {
  runApp(const IInteractApp());
}

class IInteractApp extends StatelessWidget {
  const IInteractApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iInteract',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF42A5F5)),
        useMaterial3: true,
      ),
      home: const PanelListScreen(),
    );
  }
}
