import 'dart:async';

import 'package:simplesocket/simplesocket.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

void main() {
  group('Basic integration', () {
    test(
        'Multiple signals [message-framing] https://stackoverflow.com/questions/75314786/dart-tcp-socket-concatenates-all-write-sync-calls-as-a-single-packet?noredirect=1#comment132896827_75314786.',
        () async {
      final List<String> output = <String>[];

      int thanks = 0;
      int welcome = 0;
      const int n = 10;

      Future<void> createAndDestroyMockConversationUsingSignals() async {
        final Completer<void> completer = Completer<void>();

        void defineTimeout({required int seconds}) {
          Timer(
            Duration(seconds: seconds),
            () => completer.completeError(
              TimeoutException(
                'Tried to create the server and the client, but timed out within $seconds seconds.',
              ),
            ),
          );
        }

        defineTimeout(seconds: 3);

        // Server-side.

        final SimpleServerSocket server = await SimpleServerSocket.bind();

        server.on<SimpleSocket>('connection', (SimpleSocket client) {
          output.add('1. [server]: Welcome!');

          for (int i = 0; i < n; i++) {
            client.sendSignal('welcome');
          }

          client.on<void>('thanks', (_) {
            thanks++;
            if (thanks == n) {
              client.disconnect();
            }
          });

          client.on<void>('disconnect', (_) {
            server.destroy();
          });
        });

        server.on<void>('destroy', (_) {
          completer.complete();
        });

        server.listen();

        // Client-side.

        final SimpleSocket socket =
            await SimpleSocket.connect('localhost', server.port);

        socket.on<void>('welcome', (_) {
          welcome++;

          if (welcome == n) {
            for (int i = 0; i < n; i++) {
              socket.sendSignal('thanks');
            }
          }
        });

        socket.on<void>('disconnect', (_) {
          socket.destroy();
        });

        return completer.future;
      }

      try {
        await createAndDestroyMockConversationUsingSignals();
        expect(thanks, equals(n));
        expect(welcome, equals(n));
      } on TimeoutException catch (e) {
        fail('$e');
      }
    });

    test('Send signal.', () async {
      final List<String> output = <String>[];

      Future<void> createAndDestroyMockConversationUsingSignals() async {
        final Completer<void> completer = Completer<void>();

        void defineTimeout({required int seconds}) {
          Timer(
            Duration(seconds: seconds),
            () => completer.completeError(
              TimeoutException(
                'Tried to create the server and the client, but timed out within $seconds seconds.',
              ),
            ),
          );
        }

        defineTimeout(seconds: 3);

        // Server-side.

        final SimpleServerSocket server = await SimpleServerSocket.bind();

        server.on<SimpleSocket>('connection', (SimpleSocket client) {
          output.add('1. [server]: Welcome!');
          client.sendSignal('welcome');

          client.on<void>('thanks', (_) {
            output.add('3. [server]: Bye!');
            client.destroy();
          });

          client.on<void>('disconnect', (_) {
            output.add('4. [server]: I am leaving.');
            server.destroy();
          });
        });

        server.on<void>('destroy', (_) {
          output.add('6. [server]: -- leaves --.');
          completer.complete();
        });

        server.listen();

        // Client-side.

        final SimpleSocket socket =
            await SimpleSocket.connect('localhost', server.port);

        socket.on<void>('welcome', (_) {
          output.add('2. [client]: Thanks!');
          socket.replyWithSignal('thanks');
        });

        socket.on<void>('disconnect', (_) {
          output.add('5. [client]: Okay, bye bye!');
          socket.destroy();
        });

        return completer.future;
      }

      try {
        await createAndDestroyMockConversationUsingSignals();
        expect(
          output.map((String e) => int.tryParse(e[0])),
          // Must match the expected order.
          orderedEquals(<int>[1, 2, 3, 4, 5, 6]),
        );
      } on TimeoutException catch (e) {
        fail('$e');
      }
    });
    test('Exchange contact.', () async {
      final List<String> output = <String>[];

      const String kServerPhone = '9999-9999-9999-99';
      const String kClientPhone = '0000-0000-0000-00';

      late final String clientPhoneNumber;
      late final String serverPhoneNumber;

      Future<void> createAndDestroyMockConversationUsingSignals() async {
        final Completer<void> completer = Completer<void>();

        void defineTimeout({required int seconds}) {
          Timer(
            Duration(seconds: seconds),
            () => completer.completeError(
              TimeoutException(
                'Tried to create the server and the client, but timed out within $seconds seconds.',
              ),
            ),
          );
        }

        defineTimeout(seconds: 3);

        // Server-side.

        final SimpleServerSocket server = await SimpleServerSocket.bind();

        server.on<SimpleSocket>('connection', (SimpleSocket client) {
          client.sendMessage('message', 'What is your phone number? (1)');

          client.on<List<int>?>('message', (List<int>? data) {
            if (data == null) return;

            final String message = String.fromCharCodes(data);

            final String order =
                RegExp(r'(\(.*\))').firstMatch(message)!.group(1)!;

            output.add(order.substring(1, order.length - 1));

            if (message.startsWith('My phone number is')) {
              final String phone =
                  RegExp(r'(\[.*\])').firstMatch(message)!.group(1)!;
              clientPhoneNumber = phone.substring(1, phone.length - 1);
            } else if (message.startsWith('What is yours?')) {
              client.sendMessage('message', 'Mine is: [$kServerPhone]. (4)');
            } else if (message.startsWith('Okay, I will call u tomorrow.')) {
              client.sendMessage('message', 'Okay I will wait for it. (6)');
              client.destroy();
            }
          });

          client.on<void>('disconnect', (_) {
            server.destroy();
          });
        });

        server.on<void>('destroy', (_) {
          completer.complete();
        });

        server.listen();

        // Client-side.

        final SimpleSocket socket =
            await SimpleSocket.connect('localhost', server.port);

        socket.on<List<int>?>('message', (List<int>? data) {
          if (data == null) return;

          final String message = String.fromCharCodes(data);

          final String order =
              RegExp(r'(\(.*\))').firstMatch(message)!.group(1)!;

          output.add(order.substring(1, order.length - 1));

          if (message.startsWith('What is your phone number?')) {
            socket.reply('message', 'My phone number is: [$kClientPhone]. (2)');
            socket.reply('message', 'What is yours? (3)');
          } else if (message.startsWith('Mine is')) {
            final String phone =
                RegExp(r'(\[.*\])').firstMatch(message)!.group(1)!;
            serverPhoneNumber = phone.substring(1, phone.length - 1);
            socket.reply('message', 'Okay, I will call u tomorrow. (5)');
          }
        });

        socket.on<void>('disconnect', (_) {
          socket.destroy();
        });

        return completer.future;
      }

      try {
        await createAndDestroyMockConversationUsingSignals();
        expect(
          output.map((String e) => int.tryParse(e[0])),
          // Must match the expected order.
          orderedEquals(<int>[1, 2, 3, 4, 5, 6]),
        );
        expect(clientPhoneNumber, equals(kClientPhone));
        expect(serverPhoneNumber, equals(kServerPhone));
      } on TimeoutException catch (e) {
        fail('$e');
      }
    });
  });
  test('Game room', () async {
    final List<bool> outputs = <bool>[];
    final List<String> reasons = <String>[];

    Future<void> createAndDestroyMockRoomUsingSignals() async {
      final Completer<void> completer = Completer<void>();

      void defineTimeout({required int seconds}) {
        Timer(
          Duration(seconds: seconds),
          () => completer.completeError(
            TimeoutException(
              'Tried to create the server and the client, but timed out within $seconds seconds.',
            ),
          ),
        );
      }

      defineTimeout(seconds: 10);

      // Server-side.

      final SimpleServerSocket server = await SimpleServerSocket.bind();

      int id = 1;

      final Map<String, int> clientIdByAddress = <String, int>{};
      final List<int> players = <int>[];

      server.on<SimpleSocket>('connection', (SimpleSocket client) {
        clientIdByAddress.putIfAbsent(client.address, () => id++);

        const int kMaxCapacity = 3;

        final Timer kickIfInactive =
            Timer(const Duration(milliseconds: 100), () {
          client
            ..sendSignal('inactive')
            ..disconnect();
        });

        client.on<void>('join', (_) {
          kickIfInactive.cancel();

          if (players.length >= kMaxCapacity) {
            client
              ..replyWithSignal('full')
              ..disconnect();
          } else {
            players.add(clientIdByAddress[client.address]!);
            client.replyWithSignal('ok');
          }
        });
      });

      server.on<void>('destroy', (_) => completer.complete());

      server.listen();

      // Client-side.

      Future<void> spawnClient({
        required bool inactive,
        required bool isFull,
        required bool isOk,
      }) async {
        final SimpleSocket socket =
            await SimpleSocket.connect('localhost', server.port);

        socket.on<void>('ok', (_) {
          // You are in the game.
          outputs.add(isOk);
          reasons.add(
            '[spawnClient] was called with [isOk] param set to false but the server triggered the [ok] signal.',
          );
        });

        socket.on<void>('full', (_) {
          // Game is full.
          outputs.add(isFull);
          reasons.add(
            '[spawnClient] was called with [isFull] param set to false but the server triggered the [full] signal.',
          );
        });

        socket.on<void>('inactive', (_) {
          // Did not send a [join] request.
          outputs.add(inactive);
          reasons.add(
            '[spawnClient] was called with [inactive] param set to false but the server triggered the [inactive] signal.',
          );
        });

        socket.on<void>('disconnect', (_) {
          socket.destroy();
          // completer.complete();
        });

        if (inactive) {
          // Simulation of a client that does not send any signal or interaction.
        } else {
          socket.sendSignal('join');
        }
      }

      Future<void> spawnInactiveClient() =>
          spawnClient(inactive: true, isFull: false, isOk: false);

      Future<void> spawnLateClient() =>
          spawnClient(inactive: false, isFull: true, isOk: false);

      Future<void> spawnOkClient() =>
          spawnClient(inactive: false, isFull: false, isOk: true);

      await spawnInactiveClient();
      await spawnInactiveClient();
      await spawnOkClient();
      await spawnInactiveClient();
      await spawnOkClient();
      await spawnOkClient();
      await spawnLateClient();
      await spawnLateClient();
      await spawnLateClient();
      await spawnLateClient();

      // Wait inactive players be kicked out.
      await Future<void>.delayed(const Duration(milliseconds: 350));

      await server.destroy();

      return completer.future;
    }

    await createAndDestroyMockRoomUsingSignals();

    for (int i = 0; i < outputs.length; i++) {
      final bool output = outputs[i];
      expect(output, isTrue, reason: reasons[i]);
    }

    expect(
      outputs.length,
      10,
      reason:
          'There are some clients that did not trigger the properly response.',
    );
  });
}
