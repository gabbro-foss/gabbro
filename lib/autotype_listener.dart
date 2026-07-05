import 'dart:convert';
import 'dart:io';

/// Listens on a unix-domain socket for the `gabbro-autotype` trigger and fires
/// [onTrigger] when the exact token arrives (ADR-017, Linux desktop auto-type).
///
/// The path and token come from the Rust bridge (so they never duplicate the
/// canonical constants); they are passed in here so the listener is testable
/// without the native library. There is no multi-instance support: if another
/// instance already holds the socket, [start] declines rather than clobber it.
class AutotypeListener {
  AutotypeListener({
    required this.socketPath,
    required this.token,
    required this.onTrigger,
  });

  final String socketPath;
  final String token;
  final void Function() onTrigger;

  ServerSocket? _server;

  /// Bind and start listening. Returns `true` if this instance became the
  /// listener; `false` if another live instance already owns the socket.
  Future<bool> start() async {
    if (await _socketIsLive()) return false; // another instance owns autotype

    final file = File(socketPath);
    if (file.existsSync()) file.deleteSync(); // clear a stale/leftover file
    file.parent.createSync(recursive: true);

    _server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    _server!.listen(_handle);
    return true;
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  /// Whether something is already listening on the socket (a live instance),
  /// as opposed to a stale file or nothing at all.
  Future<bool> _socketIsLive() async {
    try {
      final probe = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 200),
      );
      probe.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handle(Socket socket) {
    final chunks = <int>[];
    socket.listen(
      chunks.addAll,
      onDone: () {
        if (utf8.decode(chunks, allowMalformed: true) == token) onTrigger();
      },
      onError: (_) {},
      cancelOnError: true,
    );
  }
}
