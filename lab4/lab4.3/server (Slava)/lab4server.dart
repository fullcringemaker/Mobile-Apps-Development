import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const ServerApp());
}

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WebSocket Server',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const ServerPage(),
    );
  }
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  static const int serverPort = 8080;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _serverSubscription;

  final Set<WebSocket> _clients = {};

  final List<Map<String, dynamic>> _rows = [];
  final List<String> _rawMessages = [];
  final List<String> _logs = [];
  final List<String> _addresses = [];

  int _nextId = 1;

  bool _running = false;

  @override
  void initState() {
    super.initState();

    _loadAddresses();
    _startServer();
  }

  Future<void> _loadAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final addresses = <String>[];

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!addresses.contains(address.address)) {
            addresses.add(address.address);
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _addresses
          ..clear()
          ..addAll(addresses);
      });
    } catch (error) {
      _addLog(
        'Ошибка определения IP: $error',
      );
    }
  }

  Future<void> _startServer() async {
    if (_running) {
      return;
    }

    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        serverPort,
      );

      _server = server;

      _serverSubscription = server.listen(
            (request) {
          _handleRequest(request);
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _running = true;
      });

      _addLog(
        'Сервер запущен на порту $serverPort',
      );

      await _loadAddresses();
    } catch (error) {
      _addLog(
        'Ошибка запуска сервера: $error',
      );
    }
  }

  Future<void> _stopServer() async {
    for (final client in _clients.toList()) {
      try {
        await client.close();
      } catch (_) {}
    }

    _clients.clear();

    await _serverSubscription?.cancel();

    try {
      await _server?.close(
        force: true,
      );
    } catch (_) {}

    _server = null;
    _serverSubscription = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _running = false;
    });

    _addLog(
      'Сервер остановлен',
    );
  }

  Future<void> _handleRequest(
      HttpRequest request,
      ) async {
    if (request.uri.path != '/ws') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Use /ws');

      await request.response.close();

      return;
    }

    if (!WebSocketTransformer.isUpgradeRequest(
      request,
    )) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write(
          'WebSocket connection required',
        );

      await request.response.close();

      return;
    }

    try {
      final clientIp =
          request.connectionInfo?.remoteAddress.address ??
              'unknown';

      final socket =
      await WebSocketTransformer.upgrade(
        request,
      );

      _clients.add(socket);

      if (mounted) {
        setState(() {});
      }

      _addLog(
        'Клиент подключился: $clientIp',
      );

      _addLog(
        'Подключено клиентов: ${_clients.length}',
      );

      _sendSnapshot(
        socket,
      );

      socket.listen(
            (message) {
          _handleClientMessage(
            socket,
            clientIp,
            message,
          );
        },
        onDone: () {
          _clients.remove(socket);

          if (mounted) {
            setState(() {});
          }

          _addLog(
            'Клиент отключился: $clientIp',
          );

          _addLog(
            'Подключено клиентов: ${_clients.length}',
          );
        },
        onError: (error) {
          _clients.remove(socket);

          if (mounted) {
            setState(() {});
          }

          _addLog(
            'Ошибка клиента $clientIp: $error',
          );
        },
        cancelOnError: true,
      );
    } catch (error) {
      _addLog(
        'Ошибка WebSocket: $error',
      );
    }
  }

  void _sendSnapshot(
      WebSocket socket,
      ) {
    if (socket.readyState != WebSocket.open) {
      return;
    }

    final message = {
      'type': 'snapshot',
      'rows': _rows,
    };

    socket.add(
      jsonEncode(message),
    );

    _addLog(
      'SNAPSHOT отправлен. Записей: ${_rows.length}',
    );
  }

  void _handleClientMessage(
      WebSocket socket,
      String clientIp,
      dynamic rawMessage,
      ) {
    final messageText =
    rawMessage.toString();

    _rawMessages.add(
      messageText,
    );

    _addLog(
      'ПОЛУЧЕНО от $clientIp',
    );

    _addLog(
      messageText,
    );

    try {
      final decoded =
      jsonDecode(messageText);

      if (decoded is! Map) {
        _sendError(
          socket,
          'Ожидался JSON объект',
        );

        return;
      }

      final message =
      Map<String, dynamic>.from(
        decoded,
      );

      final type =
      message['type'];

      if (type != 'save') {
        _sendError(
          socket,
          'Неизвестный тип сообщения: $type',
        );

        return;
      }

      final rawData =
      message['data'];

      if (rawData is! Map) {
        _sendError(
          socket,
          'Поле data отсутствует',
        );

        return;
      }

      final data =
      Map<String, dynamic>.from(
        rawData,
      );

      final leftWheelSpeed =
      _readInt(
        data,
        'leftWheelSpeed',
      );

      final rightWheelSpeed =
      _readInt(
        data,
        'rightWheelSpeed',
      );

      final baseSize =
      _readDouble(
        data,
        'baseSize',
      );

      final wheelRadius =
      _readDouble(
        data,
        'wheelRadius',
      );

      final row = <String, dynamic>{
        'id': _nextId,
        'leftWheelSpeed':
        leftWheelSpeed,
        'rightWheelSpeed':
        rightWheelSpeed,
        'baseSize':
        baseSize,
        'wheelRadius':
        wheelRadius,
      };

      _nextId++;

      if (mounted) {
        setState(() {
          _rows.add(row);
        });
      } else {
        _rows.add(row);
      }

      _addLog(
        'СОХРАНЕНО: '
            'id=${row['id']}, '
            'L=${row['leftWheelSpeed']}, '
            'R=${row['rightWheelSpeed']}, '
            'base=${row['baseSize']}, '
            'radius=${row['wheelRadius']}',
      );

      _broadcastSaved(
        row,
      );
    } catch (error) {
      _addLog(
        'Ошибка обработки сообщения: $error',
      );

      _sendError(
        socket,
        error.toString(),
      );
    }
  }

  int _readInt(
      Map<String, dynamic> data,
      String key,
      ) {
    final value =
    data[key];

    if (value is! num) {
      throw FormatException(
        'Поле $key должно быть числом',
      );
    }

    return value.toInt();
  }

  double _readDouble(
      Map<String, dynamic> data,
      String key,
      ) {
    final value =
    data[key];

    if (value is! num) {
      throw FormatException(
        'Поле $key должно быть числом',
      );
    }

    return value.toDouble();
  }

  void _broadcastSaved(
      Map<String, dynamic> row,
      ) {
    final message =
    jsonEncode({
      'type': 'saved',
      'row': row,
    });

    int sentCount = 0;

    for (final client
    in _clients.toList()) {
      if (client.readyState ==
          WebSocket.open) {
        client.add(
          message,
        );

        sentCount++;
      }
    }

    _addLog(
      'SAVED отправлен клиентам: $sentCount',
    );
  }

  void _sendError(
      WebSocket socket,
      String text,
      ) {
    if (socket.readyState != WebSocket.open) {
      return;
    }

    final message = {
      'type': 'error',
      'message': text,
    };

    socket.add(
      jsonEncode(message),
    );

    _addLog(
      'ERROR: $text',
    );
  }

  void _clearHistory() {
    setState(() {
      _rows.clear();
      _rawMessages.clear();

      _nextId = 1;
    });

    _addLog(
      'История состояний очищена',
    );
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  void _addLog(
      String text,
      ) {
    if (!mounted) {
      return;
    }

    final now =
    DateTime.now();

    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    setState(() {
      _logs.insert(
        0,
        '[$time] $text',
      );

      if (_logs.length > 300) {
        _logs.removeLast();
      }
    });
  }

  Widget _buildServerInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          12,
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _running
                      ? Icons.check_circle
                      : Icons.cancel,
                  color: _running
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Text(
                    _running
                        ? 'Сервер работает'
                        : 'Сервер остановлен',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _running
                      ? _stopServer
                      : _startServer,
                  child: Text(
                    _running
                        ? 'Стоп'
                        : 'Старт',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            _buildServerAddresses(),
            const SizedBox(
              height: 6,
            ),
            Wrap(
              spacing: 15,
              runSpacing: 3,
              children: [
                Text(
                  'Клиентов: ${_clients.length}',
                ),
                Text(
                  'Сообщений: ${_rawMessages.length}',
                ),
                Text(
                  'Записей: ${_rows.length}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerAddresses() {
    if (_addresses.isEmpty) {
      return const Text(
        'IP-адрес не найден',
      );
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Text(
          'Адреса сервера:',
          style: TextStyle(
            fontWeight:
            FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        for (final address
        in _addresses)
          Padding(
            padding:
            const EdgeInsets.only(
              bottom: 2,
            ),
            child: SelectableText(
              'ws://$address:$serverPort/ws',
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCurrentState() {
    if (_rows.isEmpty) {
      return const Card(
        child: Padding(
          padding:
          EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: Center(
            child: Text(
              'Состояний пока нет',
            ),
          ),
        ),
      );
    }

    final row =
        _rows.last;

    return Card(
      child: Padding(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Последнее состояние',
                    style: TextStyle(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '#${row['id']}',
                  style: const TextStyle(
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 6,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'L: ${row['leftWheelSpeed']} рад/с',
                  ),
                ),
                Expanded(
                  child: Text(
                    'R: ${row['rightWheelSpeed']} рад/с',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 3,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'База: '
                        '${(row['baseSize'] as double).toStringAsFixed(2)} м',
                  ),
                ),
                Expanded(
                  child: Text(
                    'Радиус: '
                        '${(row['wheelRadius'] as double).toStringAsFixed(2)} м',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'История состояний',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${_rows.length}',
                ),
                IconButton(
                  tooltip:
                  'Очистить историю',
                  onPressed:
                  _rows.isEmpty
                      ? null
                      : _clearHistory,
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
          ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(
              child: Text(
                'Записей пока нет',
              ),
            )
                : ListView.separated(
              padding:
              const EdgeInsets.all(
                8,
              ),
              itemCount:
              _rows.length,
              separatorBuilder:
                  (
                  context,
                  index,
                  ) {
                return const SizedBox(
                  height: 6,
                );
              },
              itemBuilder:
                  (
                  context,
                  index,
                  ) {
                final row =
                _rows[index];

                return Container(
                  width:
                  double.infinity,
                  padding:
                  const EdgeInsets.all(
                    10,
                  ),
                  decoration:
                  BoxDecoration(
                    border:
                    Border.all(
                      color:
                      Colors.black12,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      10,
                    ),
                  ),
                  child:
                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        'Запись #${row['id']}',
                        style:
                        const TextStyle(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 5,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child:
                            Text(
                              'L: ${row['leftWheelSpeed']} рад/с',
                            ),
                          ),
                          Expanded(
                            child:
                            Text(
                              'R: ${row['rightWheelSpeed']} рад/с',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child:
                            Text(
                              'База: '
                                  '${(row['baseSize'] as double).toStringAsFixed(2)} м',
                            ),
                          ),
                          Expanded(
                            child:
                            Text(
                              'Радиус: '
                                  '${(row['wheelRadius'] as double).toStringAsFixed(2)} м',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogs() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Логи сервера',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${_logs.length}',
                ),
                IconButton(
                  tooltip:
                  'Очистить логи',
                  onPressed:
                  _logs.isEmpty
                      ? null
                      : _clearLogs,
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
          ),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
              child: Text(
                'Логов пока нет',
              ),
            )
                : ListView.builder(
              padding:
              const EdgeInsets.all(
                8,
              ),
              itemCount:
              _logs.length,
              itemBuilder:
                  (
                  context,
                  index,
                  ) {
                return Padding(
                  padding:
                  const EdgeInsets.only(
                    bottom: 7,
                  ),
                  child: Text(
                    _logs[index],
                    style:
                    const TextStyle(
                      fontSize: 12,
                      fontFamily:
                      'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDataArea() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(
                icon: Icon(
                  Icons.history,
                ),
                text: 'История',
              ),
              Tab(
                icon: Icon(
                  Icons.receipt_long,
                ),
                text: 'Логи',
              ),
            ],
          ),
          const SizedBox(
            height: 6,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildHistory(),
                _buildLogs(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDataArea() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildHistory(),
        ),
        const SizedBox(
          width: 8,
        ),
        Expanded(
          flex: 3,
          child: _buildLogs(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final client
    in _clients.toList()) {
      client.close();
    }

    _serverSubscription?.cancel();

    _server?.close(
      force: true,
    );

    super.dispose();
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'WebSocket Server',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
              context,
              constraints,
              ) {
            final compact =
                constraints.maxWidth < 700;

            return Padding(
              padding:
              const EdgeInsets.all(
                8,
              ),
              child: Column(
                children: [
                  _buildServerInfo(),
                  _buildCurrentState(),
                  const SizedBox(
                    height: 4,
                  ),
                  Expanded(
                    child: compact
                        ? _buildMobileDataArea()
                        : _buildDesktopDataArea(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
