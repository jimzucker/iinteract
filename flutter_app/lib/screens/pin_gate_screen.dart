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
//  Stub — real implementation lands in step 7.

import 'package:flutter/material.dart';

class PinGateScreen extends StatelessWidget {
  const PinGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter PIN')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('PIN screen — step 7'),
        ),
      ),
    );
  }
}
