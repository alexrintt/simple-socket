import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:events_emitter/events_emitter.dart' hide Event;

/// [ServerSocket] wrapper that extends [EventEmitter] and take care of
/// listener and socket subscriptions. Can be easily disposed through [destroy] method.
///
/// You can use the extension method [asSimpleServerSocket] to parse an existing
/// instance of a [ServerSocket] or create a new instance through [bind] static method.
///
/// Call [listen] to start listening on the provided server socket [port].
///
/// If you are passing a [ServerSocket] instance, do not use it outside of [this]
/// class, otherwise it can cause some buggy or inconsistent behavior. This
/// happes because [ServerSocket] implements [Stream], which can be subscribed only once.
///
/// Basic usage:
///
/// ```dart
/// // Creates a new server in a random port in the current network context.
/// final SimpleServerSocket server = await SimpleServerSocket.bind();
///
/// // Creates a new server in the port 3000 in the current network context.
/// // Throws the default OS error if port is not available.
/// final SimpleServerSocket server = await SimpleServerSocket.bind(port: 3000);
/// ```
class SimpleServerSocket extends EventEmitter {
  SimpleServerSocket({required this.serverSocket});

  void listen() {
    _setupSocketListener();
  }

  /// Current server socket attached port.
  ///
  /// Alias for [ServerSocket.port].
  int get port => serverSocket.port;

  /// Constant that defines the [disconnection] event.
  ///
  /// Called every time a previously connected client is disconnected.
  static const String kDisconnectionEvent = 'disconnection';

  /// Constant that defines the [connection] event.
  ///
  /// Called every time a new client connection is established.
  static const String kConnectionEvent = 'connection';

  /// Constant that defines the [destroy] event.
  ///
  /// Called after the server is shut down using [destroy].
  static const String kDestroyEvent = 'destroy';

  /// Returns a random unused port. Optionally set the [address] or [host].
  ///
  /// The following order is used to define the address passed to the [ServerSocket]
  /// constructor: [address], [host], and if not provided, we use the default
  /// [InternetAddress.anyIPv4] instance.
  static Future<int> getUnusedPort({
    InternetAddress? address,
    String? host,
  }) async {
    final ServerSocket serverSocket =
        await ServerSocket.bind(host ?? address ?? InternetAddress.anyIPv4, 0);

    final int port = serverSocket.port;

    await serverSocket.close();

    return port;
  }

  /// Creates a new [ServerSocket] instance then creates a new [SimpleServerSocket]
  /// instance that wraps the previous instance.
  static Future<SimpleServerSocket> bind({
    dynamic address,
    int? port,
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) async {
    final dynamic targetAddress = address ?? InternetAddress.anyIPv4;

    Future<int> unusedPort() async {
      if (targetAddress is InternetAddress) {
        return getUnusedPort(address: targetAddress);
      } else if (targetAddress is String) {
        return getUnusedPort(host: targetAddress);
      } else {
        return getUnusedPort();
      }
    }

    final ServerSocket serverSocket = await ServerSocket.bind(
      targetAddress,
      port ?? await unusedPort(),
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    );

    return serverSocket.asSimpleServerSocket();
  }

  /// Destroy the connection between this server and all it's clients, in both directions.
  Future<void> destroy() {
    for (final SimpleSocket socket in clients) {
      socket.destroy();
    }
    return serverSocket.close();
  }

  /// The [ServerSocket] instance that feeds the current [SimpleServerSocket] instance.
  final ServerSocket serverSocket;

  /// List of all connected clients, use `this.on<SimpleSocket>('connection')` and
  /// `this.on<SimpleSocket>('disconnection')` to be aware when this list is updated.
  final List<SimpleSocket> clients = <SimpleSocket>[];

  Future<void> _handleNewClientConnection(Socket clientSocket) async {
    final SimpleSocket clientSimpleSocket = clientSocket.asSimpleSocket();

    clients.add(clientSimpleSocket);

    clientSimpleSocket.on<void>('disconnect', (_) {
      clients.remove(clientSimpleSocket);
      emit<SimpleSocket>(kDisconnectionEvent, clientSimpleSocket);
    });

    emit<SimpleSocket>(
      kConnectionEvent,
      clientSimpleSocket,
    );
  }

  void _setupSocketListener() {
    late StreamSubscription<Socket> subscription;

    Future<void> closeConnection() async {
      await subscription.cancel();
      await serverSocket.close();
      emit<void>(kDestroyEvent);
    }

    subscription = serverSocket.listen(
      _handleNewClientConnection,
      cancelOnError: true,
      onDone: closeConnection,
      onError: (_, __) => closeConnection(),
    );
  }
}

/// Wraps the [Socket] class with an [EventEmitter] architecture.
///
/// Basic usage:
/// ```dart
/// final SimpleSocket socket = await SimpleSocket.connect('yourhost, may be localhost', <port>);
///
/// // When the [Future] completes you're connected.
/// // [...].
///
/// socket.on<void>('disconnect', (_) => print('This client was disconnected'));
/// socket.on<void>('myserversignal', (_) => print('A custom server signal'));
/// socket.on<List<int?>>('message', (List<int>? data) {
///   if (data == null) return;
///
///   final String message = utf8.decode(data);
///
///   print('The server sent a message: $message');
/// });
/// ```
///
/// See also: [SimpleServerSocket].
class SimpleSocket extends EventEmitter {
  SimpleSocket({required this.socket}) {
    _setupSocketListener();
  }

  /// Internet address as string of the current socket.
  String get address => socket.address.address;

  static Future<SimpleSocket> connect(String host, int port) async {
    final Socket socket = await Socket.connect(host, port);
    return socket.asSimpleSocket();
  }

  static const String kDisconnectEvent = 'disconnect';
  static const String kWildcardEvent = '*';

  static const List<String> _kInternalEvents = <String>[
    kDisconnectEvent,
    kWildcardEvent,
  ];

  final Socket socket;

  void destroy() {
    socket.destroy();
  }

  /// Semantic version name of [destroy].
  void disconnect() => destroy();

  void send(String eventType, List<int>? data) {
    final String? encodedData = data == null ? null : base64Encode(data);

    final Map<String, dynamic> packet = <String, dynamic>{
      'data': encodedData,
      'metadata': <String, dynamic>{
        'eventType': eventType,
      },
    };

    socket.write('-${base64Encode(utf8.encode(jsonEncode(packet)))}.');
  }

  void sendMessage(
    String eventType,
    String message, {
    Encoding encoding = utf8,
  }) {
    return send(eventType, encoding.encode(message));
  }

  void sendSignal(String eventType, {Encoding encoding = utf8}) {
    return send(eventType, null);
  }

  /// Alias for [sendMessage] to make more intuitive to work with
  /// response based messages.
  void reply(String eventType, String message, {Encoding encoding = utf8}) {
    return sendMessage(eventType, message, encoding: encoding);
  }

  void replyWithSignal(String type) {
    return send(type, null);
  }

  void _setupSocketListener() {
    late StreamSubscription<List<int>> subscription;

    Future<void> cancelSubscription() async {
      await subscription.cancel();
      socket.destroy();
      emit<void>(kDisconnectEvent);
    }

    subscription = socket.listen(
      _handleServerPacket,
      cancelOnError: true,
      onDone: cancelSubscription,
      onError: (_, __) => cancelSubscription(),
    );
  }

  String parsed = '';

  void _handleServerPacket(List<int> rawPacket) {
    final String packet = utf8.decode(rawPacket);

    final String next = parsed + packet;

    final List<String> items = <String>[];
    final List<String> tokens = next.split('');

    for (int i = 0; i < tokens.length; i++) {
      final String char = tokens[i];

      if (char == '-') {
        if (items.isNotEmpty) {
          // malformatted packet.
          items.clear();
          continue;
        }
        items.add('');
        continue;
      } else if (char == '.') {
        if (items.isEmpty) {
          // malformatted packet.
          items.clear();
          continue;
        }
        _handleCompletePacket(items.removeLast());
        continue;
      } else {
        if (items.isEmpty) {
          // malformatted packet.
          items.clear();
          continue;
        }

        items.last = items.last + char;
        continue;
      }
    }

    if (items.isNotEmpty) {
      // the last data of this packet was left incomplete.
      // cache it to complete with the next packet.
      parsed = items.last;
    }
  }

  void _handleCompletePacket(String rawPacket) {
    final _Packet? packet = _parsePacketData(
      rawPacket,
      forbiddenEventTypes: _kInternalEvents,
    );

    if (packet == null) return;

    // Emit a normal nullable event.
    emit<List<int>?>(packet.eventType, packet.data);
    emit<Event<List<int>?>>(
      kWildcardEvent,
      Event<List<int>?>(packet.eventType, packet.data),
    );
  }

  _Packet? _parsePacketData(
    String rawPacket, {
    List<String> forbiddenEventTypes = const <String>[],
  }) {
    late final dynamic packet;

    try {
      packet = jsonDecode(utf8.decode(base64Decode(rawPacket)));
    } on FormatException {
      packet = null;
    }

    if (packet is! Map<String, dynamic>) {
      // we didn't send this.
      return null;
    }

    if (packet['data'] is! String?) {
      return null;
    }

    if (packet['metadata'] is! Map<String, dynamic>) {
      return null;
    }

    final Map<String, dynamic> metadata =
        packet['metadata'] as Map<String, dynamic>;

    if (metadata['eventType'] is! String) {
      return null;
    }

    final String eventType = metadata['eventType'] as String;

    if (forbiddenEventTypes.contains(eventType)) {
      // internal events are intended to be triggered by the class,
      // not by a server packet.
      return null;
    }

    final String? encodedData = packet['data'] as String?;
    final List<int>? data =
        encodedData != null ? base64Decode(encodedData) : null;

    return _Packet(eventType: eventType, data: data);
  }
}

class Event<T> {
  const Event(this.type, this.data);

  final String type;
  final T data;
}

class _Packet {
  const _Packet({
    required this.eventType,
    required this.data,
  });

  final String eventType;
  final List<int>? data;
}

extension AsSimpleSocket on Socket {
  SimpleSocket asSimpleSocket() => SimpleSocket(socket: this);
}

extension AsSimpleServerSocket on ServerSocket {
  SimpleServerSocket asSimpleServerSocket() =>
      SimpleServerSocket(serverSocket: this);
}
