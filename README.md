# Simple socket library for Dart

A simple library to work with Dart sockets.

The [socket-io NodeJS port for Dart](https://github.com/rikulo/socket.io-client-dart) is pretty good but it has missing type definitions and I don't like to work with `dynamic` data type. Also, it is pretty heavy, I don't need all that stuff, all I want is to make sure I have a minimal intuitive library that I can work on top of Dart socket classes without worrying about leaking the memory because I forgot the 9th Stream listener opened.

Current implemented features:

- Server-side supported.
- Client-side supported.
- Message-framing through `send` APIs.
- Fully-typed API although optional.
- Lightweight: less than 400 lines of code.
- Event-driven callbacks.
- Custom event types.

Basic usage:

```dart
final SimpleServerSocket server = await SimpleServerSocket.bind();

server.on<SimpleSocket>('connection', (SimpleSocket client) {
  // or: client.sendMessage('hello', 'Hi, client.');
  client.sendSignal('hello');

  client.on<void>('bye', (_) => server.destroy());
});

server.listen();

// On client-side:

final SimpleSocket socket =
    await SimpleSocket.connect('localhost', server.port);

socket.on<void>('hello', (_) => socket.replyWithSignal('bye'));
```

Using messages:

```dart
final SimpleServerSocket server = await SimpleServerSocket.bind();

server.on<SimpleSocket>('connection', (SimpleSocket client) {
  client.sendMessage('greetings', 'Sup client!');

  client.on<List<int>>('bye', (List<int> data) {
    print(String.fromCharCodes(data)); // Bye bye...
    server.destroy();
  });
});

server.listen();

// On client-side:

final SimpleSocket socket =
    await SimpleSocket.connect('localhost', server.port);

socket.on<List<int>>('greetings', (List<int> data) {
  print(String.fromCharCodes(data)); // Sup client!
  socket.reply('bye', 'Bye bye...');
});
```

<details>
  <summary>That's what looks like working with raw Dart sockets.</summary>

```dart
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
```

</details>

## Further reading

- Message Framing - <https://blog.stephencleary.com/2009/04/message-framing.html>.
- How to create TCP message framing for the stream - <https://stackoverflow.com/questions/47382549/how-to-create-tcp-message-framing-for-the-stream>.
- Dart TCP socket concatenates all 'write' sync calls as a single packet - <https://stackoverflow.com/questions/75314786/dart-tcp-socket-concatenates-all-write-sync-calls-as-a-single-packet>.

<samp>

<h2 align="center">
  Open Source
</h2>
<p align="center">
  <sub>Copyright © 2022-present, Alex Rintt.</sub>
</p>
<p align="center">Tic Tac Toe <a href="/LICENSE">is MIT licensed 💖</a></p>
<p align="center">
  <img src="https://user-images.githubusercontent.com/51419598/169544818-f9cf92e3-f739-462e-a93c-2338730e04a9.png" width="35" />
</p>
