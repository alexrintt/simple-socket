import 'dart:async';
import 'dart:io';

void main() async {
  final ServerSocket server =
      await ServerSocket.bind(InternetAddress.anyIPv4, 0);

  late final StreamSubscription<Socket> onNewClientListener;

  Future<void> closeServer() async {
    await onNewClientListener.cancel();
    await server.close();
  }

  onNewClientListener = server.listen(
    (Socket client) {
      late final StreamSubscription<String> onNewMessageListener;

      Future<void> cancelListener() async {
        await onNewMessageListener.cancel();
      }

      client.write('Sup client!');

      onNewMessageListener = client.map(String.fromCharCodes).listen(
        // No TCP messaging-frame support!
        (String message) {
          print(message);
          if (message == 'bye') {
            client.close();
            closeServer();
          }
        },
        cancelOnError: true,
        onDone: cancelListener,
        onError: (_) => cancelListener(),
      );
    },
    cancelOnError: true,
    onDone: closeServer,
    onError: (_) => closeServer(),
  );

  // On client-side.

  final Socket socket = await Socket.connect('localhost', server.port);

  late final StreamSubscription<String> onNewServerMessageListener;

  Future<void> cancelListener() async {
    socket.destroy();
    await socket.close();
    await onNewServerMessageListener.cancel();
  }

  onNewServerMessageListener = socket.map(String.fromCharCodes).listen(
    // No TCP messaging-frame support!
    (String message) {
      if (message.startsWith('Sup')) {
        print(message);
        socket.write('bye');
      }
    },
    cancelOnError: true,
    onDone: cancelListener,
    onError: (_) => cancelListener(),
  );
}
