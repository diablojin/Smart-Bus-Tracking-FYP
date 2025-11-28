// mqtt_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Single message used by CommuterMapPage
/// 
/// Note: routeId and busId are human-readable CODES (strings), not numeric IDs.
/// - routeId: route code from routes.code, e.g. "750"
/// - busId: bus code from buses.code, e.g. "750-A"
class BusLocationUpdate {
  final String routeId; // Route code (e.g. "750"), not numeric ID
  final String busId; // Bus code (e.g. "750-A"), not numeric ID
  final double lat;
  final double lng;
  final DateTime timestamp;
  final String status;

  BusLocationUpdate({
    required this.routeId,
    required this.busId,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.status,
  });
}

class MqttService {
  // TODO: put your real HiveMQ host/port/credentials here
  static const String _broker = '39816d9e4ba848f29f7a4a572d76b661.s1.eu.hivemq.cloud'; // e.g. xxx.s2.eu.hivemq.cloud
  static const int _port = 8883; // TLS port
  static const String _username = 'fyp_mqtt';
  static const String _password = 'Fyp_mqtt123';

  late final MqttServerClient _client;

  bool _isConnected = false;
  bool _isConnecting = false;

  final _busLocationController =
      StreamController<BusLocationUpdate>.broadcast();

  Stream<BusLocationUpdate> get busLocationStream =>
      _busLocationController.stream;

  MqttService() {
    _client = MqttServerClient(_broker, '');
    _client.port = _port;
    _client.keepAlivePeriod = 30;
    _client.logging(on: false);

    // TLS
    _client.secure = true;
    _client.securityContext = SecurityContext.defaultContext;

    _client.onDisconnected = _onDisconnected;
  }

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;

    _isConnecting = true;

    final clientId =
        'flutter_${DateTime.now().millisecondsSinceEpoch.toString()}';

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(_username, _password)
        .startClean();

    _client.connectionMessage = connMessage;

    try {
      final status = await _client.connect();
      if (status?.state == MqttConnectionState.connected) {
        _isConnected = true;
        _isConnecting = false;

        // Listen for ANY incoming messages (used by commuter)
        _client.updates?.listen(_handleIncomingMessages);
      } else {
        _isConnecting = false;
        throw Exception('MQTT connect failed: ${status?.state}');
      }
    } catch (e) {
      _isConnecting = false;
      rethrow;
    }
  }

  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  void _onDisconnected() {
    _isConnected = false;
  }

  void disconnect() {
    if (_isConnected) {
      _client.disconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // COMMUTER SIDE: subscribe & decode messages
  // ---------------------------------------------------------------------------

  /// Subscribe to all bus location topics.
  /// 
  /// Topic pattern: rapidkl/bus/+/location
  /// where + matches any bus code (e.g. "750-A", "750-B")
  Future<void> subscribeToAllRoutes() async {
    await connect();
    const topic = 'rapidkl/bus/+/location';
    _client.subscribe(topic, MqttQos.atLeastOnce);
  }

  /// Handle incoming MQTT messages and decode them into BusLocationUpdate.
  /// 
  /// Expected JSON payload format:
  /// {
  ///   "routeId": "<routeCode string, e.g. '750'>",
  ///   "busId": "<busCode string, e.g. '750-A'>",
  ///   "lat": <double>,
  ///   "lng": <double>,
  ///   "status": "<string status e.g. 'In Service'>",
  ///   "timestamp": "<ISO8601 UTC timestamp>"
  /// }
  void _handleIncomingMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      try {
        final message = event.payload as MqttPublishMessage;
        final payloadString =
            MqttPublishPayload.bytesToStringAsString(message.payload.message);

        final Map<String, dynamic> data = jsonDecode(payloadString);

        // Extract routeId and busId as strings (codes, not numeric IDs)
        final routeId = data['routeId'] as String?;
        final busId = data['busId'] as String?;
        final lat = data['lat'];
        final lng = data['lng'];
        final timestampStr = data['timestamp'] as String?;
        final status = (data['status'] as String?) ?? 'In Service';

        // Validate required fields
        if (routeId == null || busId == null || lat == null || lng == null || timestampStr == null) {
          continue; // Skip malformed messages
        }

        final update = BusLocationUpdate(
          routeId: routeId, // Route code (e.g. "750")
          busId: busId, // Bus code (e.g. "750-A")
          lat: (lat as num).toDouble(),
          lng: (lng as num).toDouble(),
          timestamp: DateTime.parse(timestampStr),
          status: status,
        );

        _busLocationController.add(update);
      } catch (e) {
        // Silently skip malformed messages to prevent crashes
        // In production, you might want to log this for debugging
        continue;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // DRIVER SIDE: publish GPS updates
  // ---------------------------------------------------------------------------

  /// Publish a single GPS update for a bus.
  ///
  /// Parameters:
  /// - routeId: Route code (string, e.g. "750"), not numeric ID
  /// - busId: Bus code (string, e.g. "750-A"), not numeric ID
  /// - lat, lng: GPS coordinates
  /// - status: Bus status string (e.g. "In Service", "Delayed", "Breakdown")
  ///
  /// Publishes to topic: rapidkl/bus/{busCode}/location
  /// Payload format matches the JSON structure expected by commuter subscribers.
  Future<void> publishBusLocation({
    required String routeId, // Route code (e.g. "750")
    required String busId, // Bus code (e.g. "750-A")
    required double lat,
    required double lng,
    String status = 'In Service',
  }) async {
    await connect(); // Ensure connection before publishing

    if (!isConnected) {
      throw Exception('MQTT client is not connected');
    }

    // Topic format: rapidkl/bus/{busCode}/location
    // where busCode is the bus code (e.g. "750-A"), not a numeric ID
    final topic = 'rapidkl/bus/$busId/location';

    // Construct JSON payload matching the expected format
    final payloadMap = {
      'routeId': routeId, // Route code (string)
      'busId': busId, // Bus code (string)
      'lat': lat,
      'lng': lng,
      'status': status,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final payloadString = jsonEncode(payloadMap);

    final builder = MqttClientPayloadBuilder();
    builder.addString(payloadString);

    _client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: false,
    );
  }

  void dispose() {
    _busLocationController.close();
    disconnect();
  }
}
