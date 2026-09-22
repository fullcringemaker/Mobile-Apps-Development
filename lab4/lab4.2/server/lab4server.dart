import 'dart:convert';
import 'dart:io';

const int serverPort = 8080;

final File storageFile = File('robot_log.json');

final List<Map<String, dynamic>> logRows = [];

final Set<WebSocket> clients = {};

int nextId = 1;

Future<void> main() async {
  await loadData();

  final server = await HttpServer.bind(
    InternetAddress.anyIPv4,
    serverPort,
  );

  print('====================================');
  print('WebSocket server started');
  print('Port: $serverPort');
  print('====================================');

  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  print('');
  print('Possible addresses for phone:');

  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      print('ws://${address.address}:$serverPort/ws');
    }
  }

  print('');
  print('Waiting for connections...');
  print('');

  await for (final request in server) {
    if (request.uri.path != '/ws') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Use /ws');

      await request.response.close();
      continue;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket connection required');

      await request.response.close();
      continue;
    }

    final socket = await WebSocketTransformer.upgrade(request);

    clients.add(socket);

    final clientAddress = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    print('Client connected: $clientAddress');

    sendSnapshot(socket);

    socket.listen((message) {
        handleMessage(socket, message);
      },
      onDone: () {
        clients.remove(socket);

        print('Client disconnected: $clientAddress');
      },
      onError: (error) {
        clients.remove(socket);

        print('Client error: $error');
      },
      cancelOnError: true,
    );
  }
}

Future<void> loadData() async {
  if (!await storageFile.exists()) {
    await storageFile.writeAsString('[]');

    print('New storage file created');
    return;
  }

  try {
    final text = await storageFile.readAsString();

    if (text.trim().isEmpty) {
      return;
    }

    final decoded = jsonDecode(text);

    if (decoded is! List) {
      return;
    }

    logRows.clear();

    for (final item in decoded) {
      if (item is Map) {
        final row = Map<String, dynamic>.from(item);

        logRows.add(row);

        final id = (row['id'] as num).toInt();

        if (id >= nextId) {
          nextId = id + 1;
        }
      }
    }

    print('Loaded records: ${logRows.length}');
  } catch (error) {
    print('Storage loading error: $error');
  }
}

Future<void> saveData() async {
  final text = const JsonEncoder.withIndent(' ').convert(logRows);

  await storageFile.writeAsString(text);
}

void sendSnapshot(WebSocket socket) {
  final message = {
    'type': 'snapshot',
    'rows': logRows,
  };

  socket.add(jsonEncode(message));
}

Future<void> handleMessage(WebSocket socket, dynamic rawMessage) async {
  try {
    final decoded = jsonDecode(rawMessage.toString());

    if (decoded is! Map) {
      sendError(socket, 'Incorrect message format');
      return;
    }

    final message = Map<String, dynamic>.from(decoded);

    final type = message['type'];

    if (type == 'getSnapshot') {
      sendSnapshot(socket);
      return;
    }

    if (type == 'save') {
      final rawData = message['data'];

      if (rawData is! Map) {
        sendError(socket, 'Data field is missing');
        return;
      }

      final data = Map<String, dynamic>.from(rawData);

      final leftWheelSpeed = data['leftWheelSpeed'];
      final rightWheelSpeed = data['rightWheelSpeed'];
      final baseSize = data['baseSize'];
      final wheelRadius = data['wheelRadius'];

      if (leftWheelSpeed is! num || rightWheelSpeed is! num || baseSize is! num || wheelRadius is! num) {
        sendError(socket, 'Incorrect robot values');
        return;
      }

      final row = <String, dynamic>{
        'id': nextId,
        'leftWheelSpeed': leftWheelSpeed.toInt(),
        'rightWheelSpeed': rightWheelSpeed.toInt(),
        'baseSize': baseSize.toDouble(),
        'wheelRadius': wheelRadius.toDouble(),
      };

      nextId++;

      logRows.add(row);

      await saveData();

      print(
        'Saved: '
            'id=${row['id']}, '
            'left=${row['leftWheelSpeed']}, '
            'right=${row['rightWheelSpeed']}, '
            'base=${row['baseSize']}, '
            'radius=${row['wheelRadius']}',
      );

      broadcast({
        'type': 'saved',
        'row': row,
      });
      return;
    }

    sendError(socket, 'Unknown message type: $type');
  } catch (error) {
    sendError(socket, 'Server error: $error');
  }
}

void broadcast(Map<String, dynamic> message,) {
  final text = jsonEncode(message);

  final disconnectedClients = <WebSocket>[];

  for (final client in clients) {
    try {
      client.add(text);
    } catch (_) {
      disconnectedClients.add(client);
    }
  }

  for (final client in disconnectedClients) {
    clients.remove(client);
  }
}

void sendError(WebSocket socket, String message,) {
  socket.add(
    jsonEncode({
      'type': 'error',
      'message': message,
    }),
  );
}
