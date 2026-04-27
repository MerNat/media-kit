/// Native-only integration tests for `PlayerConfiguration.network`.
///
/// Lives under `test/src/player/native/...` so the web CI step
/// (`rm -r test/src/player/native`) drops the entire file before
/// `dart test --platform chrome` runs — `NativePlayer.getProperty`
/// only exists in the native (libmpv) implementation; the web stub
/// has no such method and the file would fail to compile for web.
///
/// These tests exercise the full round-trip from
/// `PlayerConfiguration.network` down into mpv's actual property
/// store. We use `NativePlayer.getProperty` to read back what mpv
/// actually has, which is the only honest way to verify our config
/// landed: a unit test on `NetworkConfiguration.buildStreamLavfOptions()`
/// proves the *string* is correct, but says nothing about whether the
/// native init code actually forwards it. These do.
import 'package:test/test.dart';

import 'package:media_kit/src/media_kit.dart';
import 'package:media_kit/src/models/network_configuration.dart';
import 'package:media_kit/src/player/player.dart';
import 'package:media_kit/src/player/platform_player.dart';
import 'package:media_kit/src/player/native/player/player.dart';
import 'package:media_kit/src/player/web/player/player.dart';

void main() {
  setUp(() {
    MediaKit.ensureInitialized();
    // Skip video / audio driver init in unit-tests.
    NativePlayer.test = true;
    WebPlayer.test = true;
  });

  test(
    'player-network-configuration-default-leaves-stream-lavf-o-unset',
    () async {
      final player = Player();
      // Wait for init so getProperty() reflects the configured value.
      await player.platform!.waitForPlayerInitialization;

      final native = player.platform! as NativePlayer;
      final value = await native.getProperty('stream-lavf-o');
      // mpv returns an empty string for an unset string-list property.
      // We deliberately do NOT set this property when reconnect is
      // disabled and no extras are supplied, so mpv keeps its own
      // defaults intact.
      expect(value, isEmpty);

      await player.dispose();
    },
    timeout: Timeout(const Duration(seconds: 30)),
  );

  test(
    'player-network-configuration-enable-reconnect-applies-stream-lavf-o',
    () async {
      final player = Player(
        configuration: const PlayerConfiguration(
          network: NetworkConfiguration(enableReconnect: true),
        ),
      );
      await player.platform!.waitForPlayerInitialization;

      final native = player.platform! as NativePlayer;
      final value = await native.getProperty('stream-lavf-o');
      // mpv normalises the comma-joined list back into the same form
      // we sent. Verify each individual flag landed; we don't assert
      // the exact serialised form because mpv may reorder.
      expect(value, contains('reconnect=1'));
      expect(value, contains('reconnect_streamed=1'));
      expect(value, contains('reconnect_delay_max=10'));
      expect(value, contains('reconnect_on_network_error=1'));
      expect(value, contains('reconnect_on_http_error=4xx,5xx'));

      await player.dispose();
    },
    timeout: Timeout(const Duration(seconds: 30)),
  );

  test(
    'player-network-configuration-respects-custom-reconnect-tunings',
    () async {
      final player = Player(
        configuration: const PlayerConfiguration(
          network: NetworkConfiguration(
            enableReconnect: true,
            reconnectStreamed: false,
            reconnectDelayMaxSeconds: 30,
            reconnectOnNetworkError: false,
            reconnectOnHttpError: ['500', '502'],
          ),
        ),
      );
      await player.platform!.waitForPlayerInitialization;

      final native = player.platform! as NativePlayer;
      final value = await native.getProperty('stream-lavf-o');
      expect(value, contains('reconnect=1'));
      expect(value, isNot(contains('reconnect_streamed')));
      expect(value, contains('reconnect_delay_max=30'));
      expect(value, isNot(contains('reconnect_on_network_error')));
      expect(value, contains('reconnect_on_http_error=500,502'));

      await player.dispose();
    },
    timeout: Timeout(const Duration(seconds: 30)),
  );

  test(
    'player-network-configuration-default-network-timeout-is-five',
    () async {
      final player = Player();
      await player.platform!.waitForPlayerInitialization;

      final native = player.platform! as NativePlayer;
      // mpv reports `network-timeout` as seconds with a trailing
      // ".000000" — match by parsed value, not string equality.
      final value = await native.getProperty('network-timeout');
      expect(double.parse(value), 5);

      await player.dispose();
    },
    timeout: Timeout(const Duration(seconds: 30)),
  );

  test(
    'player-network-configuration-overrides-network-timeout',
    () async {
      final player = Player(
        configuration: const PlayerConfiguration(
          network: NetworkConfiguration(networkTimeoutSeconds: 20),
        ),
      );
      await player.platform!.waitForPlayerInitialization;

      final native = player.platform! as NativePlayer;
      final value = await native.getProperty('network-timeout');
      expect(double.parse(value), 20);

      await player.dispose();
    },
    timeout: Timeout(const Duration(seconds: 30)),
  );

  test(
    'player-network-configuration-extra-stream-options-applied-without-reconnect',
    () async {
      final player = Player(
        configuration: const PlayerConfiguration(
          network: NetworkConfiguration(
            extraStreamOptions: {'user_agent': 'media_kit_test/1.0'},
          ),
        ),
      );
      await player.platform!.waitForPlayerInitialization;

      final native = player.platform! as NativePlayer;
      final value = await native.getProperty('stream-lavf-o');
      expect(value, contains('user_agent=media_kit_test/1.0'));
      // No reconnect flags — extras alone shouldn't pull in reconnect.
      expect(value, isNot(contains('reconnect=1')));

      await player.dispose();
    },
    timeout: Timeout(const Duration(seconds: 30)),
  );
}
