import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/status.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum MessageType {
  blank("blank"),
  reboot("reboot"),
  linkDevice("link-device"),
  rootPassword("root-password");

  final String value;
  const MessageType(this.value);

  static MessageType fromValue(String value) {
    return MessageType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => throw ArgumentError('Invalid MessageType: $value'),
    );
  }
}

class Message {
  final MessageType type;
  final Map<String, dynamic>? data;

  Message({required this.type, this.data}) {}

  factory Message.fromJSON(Map<String, dynamic> json) {
    final data = json['data'];
    final MessageType type = MessageType.fromValue(json['type'] as String);

    return Message(data: data, type: type);
  }
}

class Response {
  final int status;
  final Map<String, dynamic> data;

  Response({required this.status, required this.data});

  factory Response.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as int;
    final data = json['data'] as Map<String, dynamic>;

    return Response(status: status, data: data);
  }

  bool get isError {
    return status >= 300;
  }

  Message get message {
    if (isError) throw StateError('Response error: status=$status data=$data');
    return Message.fromJSON(data);
  }
}

class Channel {
  final String url;
  WebSocketChannel? _channel;

  bool _closed = false;
  void Function()? onDisconnect;
  void Function(Channel channel)? onConnect;
  final _controller = StreamController<Response>.broadcast();

  Channel(this.url, {this.onConnect, this.onDisconnect});

  Future<void> connect() async {
    _closed = false;
    _channel = WebSocketChannel.connect(Uri.parse(url));
    onConnect?.call(this);
    _channel?.stream.listen((event) {
      debugPrint('event=/s$event');
      _controller.add(_parseResponse(event));
    }, onError: (error) {
      debugPrint('webscocket error $error');
    }, onDone: () {
      debugPrint('websocket disconnected');
      onDisconnect?.call();
      if (!_controller.isClosed) {
        _controller.close();
      }
    });
  }

  void close() {
    _closed = true;
    _channel?.sink.close(goingAway);
  }

  void send(Map<String, dynamic> data) {
    if (_closed) return;
    _channel?.sink.add(jsonEncode(data));
  }

  Stream<Response> get stream => _controller.stream;

  Response _parseResponse(dynamic event) {
    final decoded = jsonDecode(event);
    return Response.fromJson(decoded);
  }
}
