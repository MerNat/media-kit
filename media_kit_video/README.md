# [package:media_kit_video](https://github.com/media-kit/media-kit)

[![](https://img.shields.io/discord/1079685977523617792?color=33cd57&label=Discord&logo=discord&logoColor=discord)](https://discord.gg/h7qf2R9n57) [![Github Actions](https://github.com/media-kit/media-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/media-kit/media-kit/actions/workflows/ci.yml)

Native implementation for video playback in [package:media_kit](https://pub.dev/packages/media_kit).

## Picture-in-Picture

Declarative PiP on iOS 15+ and Android 8.0+ (API 26):

```dart
Video(
  controller: videoController,
  pauseUponEnteringBackgroundMode: false, // required with `pip:`
  pip: const PipConfig(autoEnter: true, preferredSize: Size(16, 9)),
  onPipEvent: (event) { /* optional */ },
)
```

Imperative control via `videoController.pictureInPicture.start(...) / .stop()`.

### Events

`PipDidStop` (user tapped PiP to expand back) vs `PipClosed` (user dismissed via X / swipe) is the most useful distinction — keep playing on expand, pause/stop on close. Other events: `PipWillStart`, `PipDidStart`, `PipWillStop`, `PipFailed`, `PipRestore`, `PipSetPlaying`.

### Platform setup

**iOS** — `audio` background mode in `Info.plist`.

**Android** — on the host Activity in `AndroidManifest.xml`:

```xml
android:supportsPictureInPicture="true"
android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
android:resizeableActivity="true"
```

**Flutter on Android** — `MainActivity` must extend `FlutterFragmentActivity` (not `FlutterActivity`). PiP exit detection uses `addOnPictureInPictureModeChangedListener`, which only exists on `androidx.activity.ComponentActivity`.

### Tips

- Pass `pauseUponEnteringBackgroundMode: false` alongside `pip:` — the default pauses on background, which is when PiP starts.
- Hide your player chrome at PiP size (use `LayoutBuilder`, render bare `Video` when `constraints.maxHeight < 400`).
- If your app has multiple `Video` widgets sharing a controller, re-call `pictureInPicture.start(...)` on the surviving widget after one is disposed — disposal clears `setAutoEnterEnabled` globally on Android.

### Platform support

iOS < 15 and Android < 26 silently no-op. Desktop and web are no-ops. Auto-enter on home gesture needs Android 12 (API 31); 8.0–11 must call `start(...)` imperatively. Android TV / Fire TV typically lack PiP and gracefully no-op.

## License

Copyright © 2021 & onwards, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](./LICENSE) file.
