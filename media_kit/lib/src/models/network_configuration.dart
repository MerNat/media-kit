/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

/// {@template network_configuration}
///
/// NetworkConfiguration
/// --------------------
///
/// Tunes how the underlying libmpv / ffmpeg stack behaves when reading
/// media from the network. The defaults preserve historical media_kit
/// behaviour (no auto-reconnect, 5 second `network-timeout`).
///
/// **When to enable [enableReconnect]:** long-running live streams
/// (HLS, DASH, MPEG-TS over HTTP) where transient TCP drops, server
/// 5xx errors, or 4xx on stale segments would otherwise wedge playback
/// indefinitely. With reconnect enabled, ffmpeg silently reopens the
/// HTTP connection and resumes the stream without surfacing an error.
///
/// **What it does NOT do:** detect "silent stalls" where the socket
/// stays open but the upstream stops sending data without erroring.
/// Those still require a position-watchdog in your application code,
/// listening on `Player.stream.position` / `Player.stream.buffering`.
///
/// All fields are forwarded as ffmpeg options on the `stream-lavf-o`
/// mpv property — see <https://ffmpeg.org/ffmpeg-protocols.html#http>
/// for the full list of upstream options.
///
/// {@endtemplate}
class NetworkConfiguration {
  /// Whether to enable ffmpeg's HTTP reconnect logic
  /// (`stream-lavf-o=reconnect=1`).
  ///
  /// Default: `false` (preserves prior media_kit behaviour).
  final bool enableReconnect;

  /// Whether to enable reconnection for streamed (live) sources. Most
  /// live IPTV / HLS streams are "streamed" from ffmpeg's perspective.
  /// Has no effect when [enableReconnect] is `false`.
  ///
  /// Maps to `reconnect_streamed=1`.
  ///
  /// Default: `true`.
  final bool reconnectStreamed;

  /// Maximum delay (in seconds) between reconnect attempts. ffmpeg uses
  /// exponential backoff up to this cap. Has no effect when
  /// [enableReconnect] is `false`.
  ///
  /// Maps to `reconnect_delay_max=<value>`.
  ///
  /// Default: `10`.
  final int reconnectDelayMaxSeconds;

  /// Whether to reconnect on generic socket-level network errors. Has
  /// no effect when [enableReconnect] is `false`.
  ///
  /// Maps to `reconnect_on_network_error=1`.
  ///
  /// Default: `true`.
  final bool reconnectOnNetworkError;

  /// HTTP status codes (or wildcards like `4xx` / `5xx`) to reconnect
  /// on. Pass an empty list to disable HTTP-level reconnect entirely.
  /// Has no effect when [enableReconnect] is `false`.
  ///
  /// Maps to `reconnect_on_http_error=<comma-joined values>`.
  ///
  /// Default: `['4xx', '5xx']`.
  final List<String> reconnectOnHttpError;

  /// Override mpv's default `network-timeout` of 5 seconds. Increase
  /// this for live streams on slow / flaky networks where 5 s isn't
  /// enough for the upstream provider to respond.
  ///
  /// Set to `null` (default) to keep mpv's 5 s default.
  final int? networkTimeoutSeconds;

  /// Extra raw `key=value` pairs appended to the `stream-lavf-o`
  /// property. Use this to set ffmpeg options not covered by the
  /// dedicated fields above. The caller is responsible for valid
  /// ffmpeg syntax — values are joined with `,` and not validated.
  ///
  /// See: <https://ffmpeg.org/ffmpeg-protocols.html#http>
  ///
  /// Default: `const {}`.
  final Map<String, String> extraStreamOptions;

  /// {@macro network_configuration}
  const NetworkConfiguration({
    this.enableReconnect = false,
    this.reconnectStreamed = true,
    this.reconnectDelayMaxSeconds = 10,
    this.reconnectOnNetworkError = true,
    this.reconnectOnHttpError = const ['4xx', '5xx'],
    this.networkTimeoutSeconds,
    this.extraStreamOptions = const {},
  });

  /// Computes the value to assign to mpv's `stream-lavf-o` property.
  ///
  /// Returns `null` when nothing needs to be applied (i.e. reconnect is
  /// disabled AND no [extraStreamOptions] were supplied) — caller
  /// should skip the property assignment entirely in that case so we
  /// don't clobber any defaults.
  ///
  /// This is a pure function — easily unit-testable without a Player.
  String? buildStreamLavfOptions() {
    final opts = <String>[];
    if (enableReconnect) {
      opts.add('reconnect=1');
      if (reconnectStreamed) {
        opts.add('reconnect_streamed=1');
      }
      opts.add('reconnect_delay_max=$reconnectDelayMaxSeconds');
      if (reconnectOnNetworkError) {
        opts.add('reconnect_on_network_error=1');
      }
      if (reconnectOnHttpError.isNotEmpty) {
        opts.add('reconnect_on_http_error=${reconnectOnHttpError.join(',')}');
      }
    }
    extraStreamOptions.forEach((k, v) => opts.add('$k=$v'));
    return opts.isEmpty ? null : opts.join(',');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetworkConfiguration) return false;
    if (other.enableReconnect != enableReconnect) return false;
    if (other.reconnectStreamed != reconnectStreamed) return false;
    if (other.reconnectDelayMaxSeconds != reconnectDelayMaxSeconds) return false;
    if (other.reconnectOnNetworkError != reconnectOnNetworkError) return false;
    if (other.networkTimeoutSeconds != networkTimeoutSeconds) return false;
    if (other.reconnectOnHttpError.length != reconnectOnHttpError.length) {
      return false;
    }
    for (var i = 0; i < reconnectOnHttpError.length; i++) {
      if (other.reconnectOnHttpError[i] != reconnectOnHttpError[i]) return false;
    }
    if (other.extraStreamOptions.length != extraStreamOptions.length) {
      return false;
    }
    for (final entry in extraStreamOptions.entries) {
      if (other.extraStreamOptions[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        enableReconnect,
        reconnectStreamed,
        reconnectDelayMaxSeconds,
        reconnectOnNetworkError,
        Object.hashAll(reconnectOnHttpError),
        networkTimeoutSeconds,
        Object.hashAllUnordered(
          extraStreamOptions.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() => 'NetworkConfiguration('
      'enableReconnect: $enableReconnect, '
      'reconnectStreamed: $reconnectStreamed, '
      'reconnectDelayMaxSeconds: $reconnectDelayMaxSeconds, '
      'reconnectOnNetworkError: $reconnectOnNetworkError, '
      'reconnectOnHttpError: $reconnectOnHttpError, '
      'networkTimeoutSeconds: $networkTimeoutSeconds, '
      'extraStreamOptions: $extraStreamOptions'
      ')';
}
