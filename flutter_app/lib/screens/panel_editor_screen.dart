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
//  Stub — real implementation lands in step 6b.

import 'package:flutter/material.dart';
import '../models/panel.dart';

class PanelEditorScreen extends StatelessWidget {
  final Panel? existing;
  const PanelEditorScreen({super.key, this.existing});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(existing == null ? 'New Panel' : 'Edit Panel')),
      body: const Center(child: Text('Panel editor lands in v3.0 step 6b')),
    );
  }
}
