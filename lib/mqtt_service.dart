import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class BusLocation {
  final String busId;
  final String routeId;
  final double lat;
  final double lng;
  final DateTime timestamp;
  final String status; // 'In Service', 'Delayed', 'Breakdown'

  BusLocation({
    required this.busId,
    required this.routeId,
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.status = 'In Service',
  });

  factory BusLocation.fromJson(Map<String, dynamic> json) {
    return BusLocation(
      busId: json['busId'] as String,
      routeId: json['routeId'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as int) * 1000,
      ),
      status: json['status'] as String? ?? 'In Service',
    );
  }
}

class MqttService {
  // Singleton
  MqttService._internal();
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;

  static const String _broker =
      '39816d9e4ba848f29f7a4a572d76b661.s1.eu.hivemq.cloud';
  static const int _port = 8883;

  // TODO: replace these with the credentials YOU created
  static const String _username = 'fyp_mqtt';
  static const String _password = 'Fyp_mqtt123';

  MqttServerClient? _client;
  final _busLocationController = StreamController<BusLocation>.broadcast();

  Stream<BusLocation> get busLocationStream => _busLocationController.stream;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() async {
    if (isConnected) return;

    final client = MqttServerClient(_broker, '');
    client.logging(on: true); // turn on while debugging
    client.port = _port;
    client.secure = true;
    client.keepAlivePeriod = 20;
    client.onDisconnected = _onDisconnected;

    client.onConnected = () => print('MQTT connected');
    client.onSubscribed = (topic) => print('Subscribed to $topic');

    final connMess = MqttConnectMessage()
        .withClientIdentifier(
          'flutter-client-${DateTime.now().millisecondsSinceEpoch}',
        )
        .withWillQos(MqttQos.atMostOnce)
        .authenticateAs(_username, _password);

    client.connectionMessage = connMess;

    try {
      final res = await client.connect();
      print('MQTT: connect() return: $res');
      print(
        'MQTT: status: ${client.connectionStatus?.state}, '
        'code: ${client.connectionStatus?.returnCode}',
      );

      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        _client = client;
        print('MQTT: Connected to broker');
      } else {
        print('MQTT: Connection failed, disconnecting');
        client.disconnect();
        throw Exception(
          'Connection failed: ${client.connectionStatus?.returnCode}',
        );
      }
    } catch (e) {
      print('MQTT: Connection failed - $e');
      client.disconnect();
      rethrow;
    }
  }

  void _onDisconnected() {
    print('MQTT: Disconnected');
  }

    /// Subscribe to all buses using wildcard: bus/location/#
  Future<void> subscribeToAllBuses() async {
    if (!isConnected) {
      await connect();
    }

    const topic = 'bus/location/#';
    print('MQTT: Subscribing to all buses on $topic');
    _client!.subscribe(topic, MqttQos.atMostOnce);

    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> events) {
      final recMess = events.first.payload as MqttPublishMessage;
      final payloadBytes = recMess.payload.message;
      final payloadString = utf8.decode(payloadBytes);
      final topic = events.first.topic;

      print('MQTT: Message received on topic $topic -> $payloadString');

      try {
        final data = jsonDecode(payloadString) as Map<String, dynamic>;
        final location = BusLocation.fromJson(data);
        print('MQTT: Parsed BusLocation: '
            'busId=${location.busId}, '
            'lat=${location.lat}, lng=${location.lng}');
        _busLocationController.add(location);
      } catch (e) {
        print('MQTT: Failed to parse payload: $payloadString, error: $e');
      }
    });
  }

  /// Publish a location for a bus
    /// Publish a location for a bus on a specific route
  Future<void> publishLocation({
    required String routeId,
    required String busId,
    required double lat,
    required double lng,
    String? status,
  }) async {
    if (!isConnected) {
      await connect();
    }

    final topic = 'bus/location/$routeId/$busId';

    final payload = jsonEncode({
      'busId': busId,
      'routeId': routeId,
      'lat': lat,
      'lng': lng,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      if (status != null) 'status': status,
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    _client!.publishMessage(
      topic,
      MqttQos.atMostOnce,
      builder.payload!,
    );

    print('MQTT: Published to $topic -> $payload');
  }

    /// Subscribe to all routes and all buses: bus/location/#
  Future<void> subscribeToAllRoutes() async {
    if (!isConnected) {
      await connect();
    }

    const topic = 'bus/location/#';
    print('MQTT: Subscribing to all routes on $topic');
    _client!.subscribe(topic, MqttQos.atMostOnce);

    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> events) {
      final recMess = events.first.payload as MqttPublishMessage;
      final payloadBytes = recMess.payload.message;
      final payloadString = utf8.decode(payloadBytes);
      final topic = events.first.topic;

      print('MQTT: Message received on topic $topic -> $payloadString');

      try {
        final data = jsonDecode(payloadString) as Map<String, dynamic>;

        // Try to derive routeId / busId from JSON or from topic
        String routeId;
        String busId;

        if (data.containsKey('routeId')) {
          routeId = data['routeId'] as String;
        } else {
          // topic format: bus/location/{routeId}/{busId}
          final parts = topic.split('/');
          routeId = parts.length >= 3 ? parts[2] : 'unknown_route';
        }

        if (data.containsKey('busId')) {
          busId = data['busId'] as String;
        } else {
          final parts = topic.split('/');
          busId = parts.length >= 4 ? parts[3] : 'unknown_bus';
        }

        final statusFromData = data['status'] as String? ?? 'In Service';
        print('📦 MQTT: Raw status from JSON: "${data['status']}" -> Parsed: "$statusFromData"');

        final location = BusLocation(
          busId: busId,
          routeId: routeId,
          lat: (data['lat'] as num).toDouble(),
          lng: (data['lng'] as num).toDouble(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (data['timestamp'] as int) * 1000,
          ),
          status: statusFromData,
        );

        print('MQTT: Parsed BusLocation: '
            'routeId=${location.routeId}, busId=${location.busId}, '
            'status="${location.status}", '
            'lat=${location.lat}, lng=${location.lng}');

        _busLocationController.add(location);
      } catch (e) {
        print('MQTT: Failed to parse payload: $payloadString, error: $e');
      }
    });
  }

  Future<void> disconnect() async {
    if (_client != null) {
      print("MQTT: Disconnecting...");
      _client!.disconnect();
    }
    _client = null;
    print("MQTT: Disconnected & cleaned up");
  }
}
