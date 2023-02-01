import 'dart:async';

import 'package:simplesocket/simplesocket.dart';

/// Create a sample server.
Future<void> _createServer() async {
  final SimpleServerSocket server = await SimpleServerSocket.bind(port: 62706);

  int connection = 0;

  server.on<SimpleSocket>('connection', (SimpleSocket client) {
    print('[server] New client connected.');

    final int id = ++connection;

    client.sendMessage('receivedId', '$id');

    client.on<List<int>?>('message', (List<int>? message) {
      if (message == null) return;

      for (final SimpleSocket simpleSocket in server.clients) {
        simpleSocket.sendMessage(
          'message',
          'Client [$id] said: ${String.fromCharCodes(message)}',
        );
      }
    });

    client.on<void>(
      'disconnect',
      (_) {
        print('[server] Client $id was disconnected.');
      },
    );
  });

  server.listen();

  print('Listening on port: ${server.serverSocket.port}.');
}

Future<void> main(List<String> arguments) async {
  await _createServer();
}
