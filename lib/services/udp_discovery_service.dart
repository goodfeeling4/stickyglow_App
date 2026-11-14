import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Lightweight UDP discovery & notification listener on port 41234.
///
/// Listens for LAN beacons (e.g. `STICKY_UPDATE`) emitted by the Linux
/// desktop wallpaper daemon when notes change or the laptop connects.
class UdpDiscoveryService {
  /// Default UDP port matching the desktop broadcast daemon.
  static const int port = 41234;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  bool _isListening = false;

  /// Whether the UDP discovery listener is currently active.
  bool get isListening => _isListening;

  /// Starts listening for UDP broadcast packets on [port].
  ///
  /// Calls [onBeaconReceived] with a debounced trigger whenever a valid
  /// update beacon is detected.
  Future<void> startListening({
    required void Function() onBeaconReceived,
    int listenPort = port,
  }) async {
    if (_isListening) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        listenPort,
        reuseAddress: true,
        reusePort: true,
      );
      _isListening = true;

      Timer? debounceTimer;

      _subscription = _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            try {
              final message = utf8.decode(datagram.data).trim();
              if (message.contains('STICKY_UPDATE') ||
                  message.contains('STICKY_ONLINE')) {
                debounceTimer?.cancel();
                debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  onBeaconReceived();
                });
              }
            } catch (_) {}
          }
        }
      }, onError: (e) {
        debugPrint('UdpDiscoveryService error: $e');
        stopListening();
      }, onDone: () {
        stopListening();
      });
    } catch (e) {
      debugPrint('UdpDiscoveryService bind failed: $e');
      _isListening = false;
    }
  }

  /// Stops listening and releases the UDP socket.
  void stopListening() {
    _isListening = false;
    _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
