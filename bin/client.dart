import 'dart:io';
import 'package:simplesocket/simplesocket.dart';

Future<SimpleSocket> _createClient() async {
  final SimpleSocket socket = await SimpleSocket.connect('localhost', 62706);

  socket.on<List<int>?>('message', (List<int>? message) {
    if (message == null) return;
    stdout.write(String.fromCharCodes(message));
  });

  socket.on<void>('disconnect', (_) {
    print('[client] This client was disconnected.');
  });

  return socket;
}

Future<void> main(List<String> arguments) async {
  final SimpleSocket socket = await _createClient();

  await stdin.forEach((List<int> data) {
    final String message = String.fromCharCodes(data);

    socket.sendMessage('message', message);
  });
}
