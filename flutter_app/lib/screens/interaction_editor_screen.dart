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
//  Stub — real implementation lands in step 6c.

import 'package:flutter/material.dart';
import '../models/panel.dart';

class InteractionEditorScreen extends StatelessWidget {
  final Interaction? existing;
  const InteractionEditorScreen({super.key, this.existing});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(existing == null ? 'New Interaction' : 'Edit Interaction')),
      body: const Center(child: Text('Interaction editor lands in v3.0 step 6c')),
    );
  }
}
