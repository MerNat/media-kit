import 'package:test/test.dart';

import 'package:media_kit/src/models/network_configuration.dart';

void main() {
  group('NetworkConfiguration defaults', () {
    test('is fully default-constructible', () {
      const config = NetworkConfiguration();
      expect(config.enableReconnect, isFalse);
      expect(config.reconnectStreamed, isTrue);
      expect(config.reconnectDelayMaxSeconds, 10);
      expect(config.reconnectOnNetworkError, isTrue);
      expect(config.reconnectOnHttpError, ['4xx', '5xx']);
      expect(config.networkTimeoutSeconds, isNull);
      expect(config.extraStreamOptions, isEmpty);
    });

    test(
      'buildStreamLavfOptions returns null when nothing is configured — '
      'so the caller can skip the property assignment and preserve mpv '
      'defaults',
      () {
        const config = NetworkConfiguration();
        expect(config.buildStreamLavfOptions(), isNull);
      },
    );
  });

  group('NetworkConfiguration.buildStreamLavfOptions', () {
    test('emits the canonical reconnect set when enableReconnect is true', () {
      const config = NetworkConfiguration(enableReconnect: true);
      final value = config.buildStreamLavfOptions();
      expect(value, isNotNull);
      // Order matters because mpv parses left-to-right; verify the
      // exact serialised form so refactors don't silently drop options.
      expect(
        value,
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=10,'
        'reconnect_on_network_error=1,reconnect_on_http_error=4xx,5xx',
      );
    });

    test('reconnectStreamed=false omits the streamed flag', () {
      const config = NetworkConfiguration(
        enableReconnect: true,
        reconnectStreamed: false,
      );
      expect(config.buildStreamLavfOptions(), isNot(contains('reconnect_streamed')));
    });

    test('reconnectOnNetworkError=false omits the network-error flag', () {
      const config = NetworkConfiguration(
        enableReconnect: true,
        reconnectOnNetworkError: false,
      );
      expect(
        config.buildStreamLavfOptions(),
        isNot(contains('reconnect_on_network_error')),
      );
    });

    test('reconnectOnHttpError=[] omits the http-error flag entirely', () {
      const config = NetworkConfiguration(
        enableReconnect: true,
        reconnectOnHttpError: [],
      );
      expect(
        config.buildStreamLavfOptions(),
        isNot(contains('reconnect_on_http_error')),
      );
    });

    test('custom reconnectOnHttpError list is comma-joined', () {
      const config = NetworkConfiguration(
        enableReconnect: true,
        reconnectOnHttpError: ['403', '500', '502', '504'],
      );
      expect(
        config.buildStreamLavfOptions(),
        contains('reconnect_on_http_error=403,500,502,504'),
      );
    });

    test('reconnectDelayMaxSeconds is propagated', () {
      const config = NetworkConfiguration(
        enableReconnect: true,
        reconnectDelayMaxSeconds: 30,
      );
      expect(
        config.buildStreamLavfOptions(),
        contains('reconnect_delay_max=30'),
      );
    });

    test('extraStreamOptions are appended even without enableReconnect', () {
      const config = NetworkConfiguration(
        extraStreamOptions: {
          'user_agent': 'Nimo/1.0',
          'multiple_requests': '1',
        },
      );
      final value = config.buildStreamLavfOptions();
      expect(value, isNotNull);
      // Both keys present; we don't assert order since extras come from
      // a Map iteration which is insertion-ordered in Dart.
      expect(value, contains('user_agent=Nimo/1.0'));
      expect(value, contains('multiple_requests=1'));
    });

    test('extraStreamOptions are appended after reconnect flags', () {
      const config = NetworkConfiguration(
        enableReconnect: true,
        extraStreamOptions: {'user_agent': 'Nimo/1.0'},
      );
      final value = config.buildStreamLavfOptions()!;
      // Reconnect flags come first, then extras.
      final reconnectIdx = value.indexOf('reconnect=1');
      final uaIdx = value.indexOf('user_agent');
      expect(reconnectIdx, greaterThanOrEqualTo(0));
      expect(uaIdx, greaterThan(reconnectIdx));
    });
  });

  group('NetworkConfiguration equality', () {
    test('two default-constructed instances are equal', () {
      expect(const NetworkConfiguration(), const NetworkConfiguration());
      expect(
        const NetworkConfiguration().hashCode,
        const NetworkConfiguration().hashCode,
      );
    });

    test('differs when enableReconnect differs', () {
      expect(
        const NetworkConfiguration(),
        isNot(const NetworkConfiguration(enableReconnect: true)),
      );
    });

    test('differs when reconnectOnHttpError list contents differ', () {
      expect(
        const NetworkConfiguration(reconnectOnHttpError: ['4xx', '5xx']),
        isNot(const NetworkConfiguration(reconnectOnHttpError: ['5xx'])),
      );
    });

    test('differs when extraStreamOptions differ', () {
      expect(
        const NetworkConfiguration(extraStreamOptions: {'a': '1'}),
        isNot(const NetworkConfiguration(extraStreamOptions: {'a': '2'})),
      );
      expect(
        const NetworkConfiguration(extraStreamOptions: {'a': '1'}),
        const NetworkConfiguration(extraStreamOptions: {'a': '1'}),
      );
    });
  });

  group('NetworkConfiguration.toString', () {
    test('includes every field for diagnostics', () {
      const config = NetworkConfiguration(
        enableReconnect: true,
        networkTimeoutSeconds: 15,
        extraStreamOptions: {'foo': 'bar'},
      );
      final s = config.toString();
      expect(s, contains('enableReconnect: true'));
      expect(s, contains('reconnectStreamed: true'));
      expect(s, contains('reconnectDelayMaxSeconds: 10'));
      expect(s, contains('reconnectOnNetworkError: true'));
      expect(s, contains('reconnectOnHttpError: [4xx, 5xx]'));
      expect(s, contains('networkTimeoutSeconds: 15'));
      expect(s, contains('extraStreamOptions: {foo: bar}'));
    });
  });
}
