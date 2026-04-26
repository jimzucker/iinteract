# iinteract (Flutter)

Cross-platform Flutter port of [iInteract: i Feel, i Speak](../README.md) — the iOS/watchOS/macOS communication-board app for children with special needs. This Flutter codebase targets Android, web, and iOS/macOS where Flutter is preferred over the native UIKit app.

## v3.0 — configurable panels

The app now supports two modes (toggle in the gear → Mode):

| Mode    | What you can do                                                                                                                       |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Default | The seven built-in panels behave exactly like 1.x. Pick a boy or girl voice and that's it.                                            |
| Custom  | Hide or reorder any built-in panel, **and** create your own panels with your own photos and recorded voices (up to 6 items per page). |

When Custom is on, the app bar shows an `+` button. Tapping it opens the panel-list editor (visibility switches, drag-to-reorder, swipe-style delete on user panels). From the editor you can also set/change/clear an optional 4-digit **PIN** that gates entry; if you forget the PIN you can reset it by answering a security question you set when creating it. Five wrong attempts trigger a one-minute lockout.

**Your data stays on your device.** Photos and recordings live under Application Documents and are never uploaded to us or any third party. Cross-device sync (which the iOS app does via iCloud KVS) is **not** in this Flutter v3.0 release — the metadata stays per-install for now.

## Building

```sh
flutter pub get
flutter run                  # auto-pick a connected device
flutter run -d chrome        # web
flutter test                 # unit + widget tests
```

For a production Android upload:

```sh
cd android && ./gradlew bundleRelease
# AAB at build/app/outputs/bundle/release/app-release.aab
```

A signing key and `android/key.properties` are expected (see the top-level repo for details).
