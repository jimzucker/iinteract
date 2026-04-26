//
//  configuration_mode.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:shared_preferences/shared_preferences.dart';

enum ConfigurationMode {
  defaultMode('default'),
  custom('custom');

  final String storageValue;
  const ConfigurationMode(this.storageValue);

  static const userDefaultsKey = 'configuration_mode';

  static ConfigurationMode fromString(String? raw) {
    return ConfigurationMode.values.firstWhere(
      (m) => m.storageValue == raw,
      orElse: () => ConfigurationMode.defaultMode,
    );
  }

  static Future<ConfigurationMode> current() async {
    final prefs = await SharedPreferences.getInstance();
    return fromString(prefs.getString(userDefaultsKey));
  }

  static Future<void> set(ConfigurationMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userDefaultsKey, mode.storageValue);
  }
}
