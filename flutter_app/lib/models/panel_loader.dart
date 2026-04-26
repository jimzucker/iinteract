//
//  panel_loader.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'configuration_mode.dart';
import 'panel.dart';
import 'panel_store.dart';

/// Returns the panels to display for the current configuration mode.
///   * defaultMode: bundled built-ins, untouched (parity with v1.x).
///   * custom:      bundled + user-authored, filtered + ordered per
///                  PanelStore.layout(), and user interactions hydrated.
Future<List<Panel>> loadPanels({
  ConfigurationMode? mode,
  PanelStore? store,
}) async {
  final m = mode ?? await ConfigurationMode.current();
  final s = store ?? PanelStore.shared;
  final builtIns = builtInPanels();
  switch (m) {
    case ConfigurationMode.defaultMode:
      return builtIns;
    case ConfigurationMode.custom:
      final user = await s.userPanels();
      for (final p in user) {
        await s.hydrate(p);
      }
      final layout = await s.layout();
      return s.applyLayout([...builtIns, ...user], layout);
  }
}
