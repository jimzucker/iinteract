// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

//
//  widget_test.dart
//  iinteract
//
//  Copyright © 2015 - 2026 Jim Zucker, Cathy DeMarco, Tricia Zucker
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:iinteract/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App loads panel list', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const IInteractApp());
    // panels load asynchronously now (loadPanels reads SharedPreferences),
    // so pump-and-settle until the async setState completes.
    await tester.pumpAndSettle();
    expect(find.text('iInteract'), findsOneWidget);
    expect(find.text('I feel'), findsOneWidget);
  });
}
