import 'dart:convert';
import 'dart:io';

/// ADR-017. Path and token are passed in (from the Rust bridge) so this is
/// testable without the native library. If another instance holds the socket,
/// [start] declines rather than clobber it.
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
