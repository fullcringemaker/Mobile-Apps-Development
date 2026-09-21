import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lab 4 WebSocket',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const WheelControllerPage(),
    );
  }
}

class TrofimenkoLogRow {
  final int id;
  final int leftWheelSpeed;
  final int rightWheelSpeed;
  final double baseSize;
  final double wheelRadius;

  const TrofimenkoLogRow({
    required this.id,
    required this.leftWheelSpeed,
    required this.rightWheelSpeed,
    required this.baseSize,
    required this.wheelRadius,
  });

  factory TrofimenkoLogRow.fromJson(Map<String, dynamic> json) {
    return TrofimenkoLogRow(
      id: (json['id'] as num).toInt(),
      leftWheelSpeed: (json['leftWheelSpeed'] as num).toInt(),
      rightWheelSpeed: (json['rightWheelSpeed'] as num).toInt(),
      baseSize: (json['baseSize'] as num).toDouble(),
      wheelRadius: (json['wheelRadius'] as num).toDouble(),
    );
  }
}

class WheelControllerPage extends StatefulWidget {
  const WheelControllerPage({super.key});

  @override
  State<WheelControllerPage> createState() {
    return _WheelControllerPageState();
  }
}

class _WheelControllerPageState  extends State<WheelControllerPage> {

  static const String serverIp = '172.17.7.214';
  // 172.16.208.237

  static const int serverPort = 8080;

  WebSocket? webSocket;

  StreamSubscription<dynamic>? webSocketSubscription;

  bool isConnected = false;
  bool isConnecting = false;

  bool isServerErrorDialogShown = false;

  int leftWheelSpeed = 0;
  int rightWheelSpeed = 0;
  double baseSize = 0.4;
  double wheelRadius = 0.05;

  double robotX = 0;
  double robotY = 0;

  double robotAngle = math.pi / 2;

  bool isRunning = false;

  Timer? timer;

  static const double timeStep = 0.04;

  final List<TrofimenkoLogRow> logRows = [];

  final ScrollController logVerticalController = ScrollController();
  final ScrollController logHorizontalController = ScrollController();

  Future<void> saveQueue = Future<void>.value();

  final List<Offset> trail = [
    Offset.zero,
  ];

  @override
  void initState() {
    super.initState();

    _connectToServer();
  }

  @override
  void dispose() {
    timer?.cancel();

    webSocketSubscription?.cancel();

    webSocket?.close();

    logVerticalController.dispose();

    logHorizontalController.dispose();

    super.dispose();
  }

  void _showServerDisconnectedDialog() {
    if (!mounted || isServerErrorDialogShown) {
      return;
    }

    isServerErrorDialogShown = true;

    showDialog<void>(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ошибка соединения'),
          content: const Text('Соединение с сервером потеряно.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                isServerErrorDialogShown = false;
              },

              child: const Text('Закрыть'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                isServerErrorDialogShown = false;

                _connectToServer();
              },

              child: const Text('Переподключиться'),
            ),
          ],
        );
      },
    ).then(
          (_) {
        isServerErrorDialogShown = false;
      },
    );
  }

  Future<void> _connectToServer() async {
    if (isConnecting) {
      return;
    }

    setState(() {
      isConnecting = true;
      isConnected = false;
    });

    await webSocketSubscription?.cancel();

    await webSocket?.close();

    webSocket = null;

    try {
      final address = 'ws://$serverIp:$serverPort/ws';

      debugPrint('Connecting to $address');

      final socket = await WebSocket.connect(address).timeout(
        const Duration(
          seconds: 5,
        ),
      );

      if (!mounted) {
        await socket.close();

        return;
      }

      webSocket = socket;

      setState(() {
        isConnected = true;
        isConnecting = false;
      });

      debugPrint('WebSocket connected');

      webSocketSubscription = socket.listen(
            (message) {
              _handleServerMessage(message);
              },

            onDone: () {
              if (webSocket != socket) {
                return;
              }

              if (!mounted) {
                return;
              }

              setState(() {
                isConnected = false;
                isConnecting = false;
              });

              webSocket = null;

              debugPrint('WebSocket disconnected');

              _showServerDisconnectedDialog();
            },

            onError: (error) {
              if (webSocket != socket) {
                return;
              }

              if (!mounted) {
                return;
              }

              setState(() {
                isConnected = false;
                isConnecting = false;
              });

              webSocket = null;

              debugPrint('WebSocket error: $error',);

              _showServerDisconnectedDialog();
            },

            cancelOnError: true,
          );
    } catch (error) {

      if (!mounted) {
        return;
      }

      setState(() {
        isConnected = false;
        isConnecting = false;
      });

      debugPrint(
        'Connection error: $error',
      );

      _showServerDisconnectedDialog();
    }
  }

  void _handleServerMessage(dynamic rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage.toString(),);

      if (decoded is! Map) {
        return;
      }

      final message = Map<String, dynamic>.from(decoded,);

      final type = message['type'];

      if (type == 'snapshot') {

        final rawRows = message['rows'];

        if (rawRows is! List) {
          return;
        }

        final loadedRows = <TrofimenkoLogRow>[];

        for (final item in rawRows) {
          if (item is Map) {
            loadedRows.add(TrofimenkoLogRow.fromJson(
                Map<String, dynamic>.from(item),
              ),
            );
          }
        }

        if (!mounted) {
          return;
        }

        setState(() {
          logRows.clear();

          logRows.addAll(loadedRows,);

          if (loadedRows.isNotEmpty) {

            final last = loadedRows.last;

            leftWheelSpeed = last.leftWheelSpeed;
            rightWheelSpeed = last.rightWheelSpeed;
            baseSize = last.baseSize.clamp(0.1, 1.0).toDouble();
            wheelRadius = last.wheelRadius.clamp(0.01, 0.2).toDouble();
          }
        });

        return;
      }

      if (type == 'saved') {

        final rawRow = message['row'];

        if (rawRow is! Map) {
          return;
        }

        final row = TrofimenkoLogRow.fromJson(
          Map<String, dynamic>.from(rawRow),
        );

        if (!mounted) {
          return;
        }

        setState(() {
          final exists = logRows.any(
                (item) => item.id == row.id,
          );

          if (!exists) {
            logRows.add(row);
          }
        });

        return;
      }

      if (type == 'error') {
        debugPrint(
          'Server error: '
              '${message['message']}',
        );
      }
    } catch (error) {
      debugPrint('Message error: $error');
    }
  }

  void _scheduleSaveValues() {
    saveQueue = saveQueue.then(
          (_) async {
            await _saveValues();
          },
        );
  }

  Future<void>
  _saveValues() async {

    final socket = webSocket;

    if (!isConnected || socket == null) {

      debugPrint('Not sent: server is not connected');
      _showServerDisconnectedDialog();

      return;
    }

    final message = {
      'type': 'save',
      'data': {
        'leftWheelSpeed': leftWheelSpeed,
        'rightWheelSpeed': rightWheelSpeed,
        'baseSize': baseSize,
        'wheelRadius': wheelRadius,
      },
    };

    socket.add(jsonEncode(message));
  }

  void _restoreLogRow(TrofimenkoLogRow row) {
    setState(() {
      leftWheelSpeed = row.leftWheelSpeed;
      rightWheelSpeed = row.rightWheelSpeed;
      baseSize = row.baseSize.clamp(0.1, 1.0).toDouble();
      wheelRadius = row.wheelRadius.clamp(0.01, 0.2,).toDouble();
    });

    _scheduleSaveValues();
  }

  Future<void> _showTimeMachine() async {

    if (logRows.isEmpty) {
      return;
    }

    int selectedIndex = logRows.length - 1;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState,) {
            final row = logRows[selectedIndex];
            return AlertDialog(
              title: const Text('Машина времени'),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Запись '
                          '${selectedIndex + 1} '
                          'из ${logRows.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Row(
                      children: [
                        IconButton(
                          onPressed: selectedIndex >
                              0
                              ? () {
                            setDialogState(
                                  () {
                                selectedIndex--;
                              },
                            );
                          }
                              : null,

                          icon:
                          const Icon(Icons.chevron_left),
                        ),

                        Expanded(
                          child: Slider(
                            value: selectedIndex.toDouble(),
                            min: 0,
                            max: logRows.length >
                                1
                                ? (logRows.length - 1).toDouble()
                                : 1,

                            divisions: logRows.length >
                                1
                                ? logRows.length - 1
                                : 1,

                            onChanged:
                            logRows.length >
                                1
                                ? (value) {
                              setDialogState(
                                    () {
                                  selectedIndex = value.round();
                                },
                              );
                            }
                                : null,
                          ),
                        ),

                        IconButton(
                          onPressed: selectedIndex <
                              logRows.length - 1
                              ? () {
                            setDialogState(
                                  () {
                                selectedIndex++;
                              },
                            );
                          }
                              : null,

                          icon:
                          const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),

                    const Divider(),
                    _buildTimeMachineRow(
                      'Левое колесо',
                      '${row.leftWheelSpeed} рад/с',
                    ),
                    _buildTimeMachineRow(
                      'Правое колесо',
                      '${row.rightWheelSpeed} рад/с',
                    ),
                    _buildTimeMachineRow(
                      'Размер базы',
                      '${row.baseSize.toStringAsFixed(2)} м',
                    ),
                    _buildTimeMachineRow(
                      'Радиус колеса',
                      '${row.wheelRadius.toStringAsFixed(2)} м',
                    ),
                  ],
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },

                  child: const Text('Закрыть'),
                ),

                FilledButton(
                  onPressed: () {
                    _restoreLogRow(row);

                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Восстановить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTimeMachineRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),

      child: Row(
        children: [
          Expanded(
            child: Text(name),
          ),
          Text(
            value, style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  double get leftLinearSpeed {
    return leftWheelSpeed * wheelRadius;
  }

  double get rightLinearSpeed {
    return rightWheelSpeed * wheelRadius;
  }

  double get linearSpeed {
    return (leftLinearSpeed + rightLinearSpeed) / 2;
  }

  double get angularSpeed {
    return (rightLinearSpeed - leftLinearSpeed) / baseSize;
  }

  double? get turningRadius {
    if (angularSpeed.abs() < 0.000001) {
      return null;
    }

    return (linearSpeed / angularSpeed).abs();
  }

  String get turningRadiusText {

    if (leftWheelSpeed == 0 && rightWheelSpeed == 0) {
      return '—';
    }
    if (turningRadius == null) {
      return 'inf';
    }

    return '${turningRadius!.toStringAsFixed(3)} м';
  }

  String get movementStatus {
    if (leftWheelSpeed == 0 && rightWheelSpeed == 0) {
      return 'Стоит на месте';
    }

    if (leftWheelSpeed == rightWheelSpeed) {
      if (leftWheelSpeed > 0) {
        return 'Вперёд';
      }
      return 'Назад';
    }

    if (angularSpeed > 0) {
      return 'Поворот влево';
    }

    return 'Поворот вправо';
  }

  void _startSimulation() {

    if (isRunning) {
      return;
    }

    setState(() {
      isRunning = true;
    });

    timer = Timer.periodic(
      const Duration(
        milliseconds: 40,
      ),
          (_) {
        final currentLinearSpeed = linearSpeed;
        final currentAngularSpeed = angularSpeed;

        if (currentLinearSpeed.abs() < 0.000001 && currentAngularSpeed.abs() < 0.000001) {
          return;
        }

        setState(() {
          robotX += currentLinearSpeed * math.cos(robotAngle) * timeStep;
          robotY += currentLinearSpeed * math.sin(robotAngle) * timeStep;
          robotAngle -= currentAngularSpeed * timeStep;

          trail.add(
            Offset(
              robotX,
              robotY,
            ),
          );

          if (trail.length > 3000) {
            trail.removeAt(0);
          }
        });
      },
    );
  }

  void _stopSimulation() {

    timer?.cancel();

    timer = null;

    setState(() {
      isRunning = false;
    });
  }

  void _resetSimulation() {
    timer?.cancel();

    timer = null;

    setState(() {

      isRunning = false;

      robotX = 0;
      robotY = 0;
      robotAngle = math.pi / 2;

      trail.clear();

      trail.add(
        Offset.zero,
      );
    });
  }

  Widget _buildWheelSlider({
    required String title,
    required int value,
    required ValueChanged<int> onChanged,
    required ValueChanged<int> onChangeEnd,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title, textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$value рад/с',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Slider(
              value: value.toDouble(),
              min: -10,
              max: 10,
              divisions: 20,
              onChanged: (value) {
                onChanged(value.toInt());
              },

              onChangeEnd: (value) {
                onChangeEnd(value.toInt());
              },
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('-10'),
                Text('0'),
                Text('10'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeSlider({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required int digits,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title, textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${value.toStringAsFixed(digits)} м',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(min.toStringAsFixed(digits)),
                Text(max.toStringAsFixed(digits)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _buildWheelSlider(
                  title: 'Скорость левого колеса',
                  value: leftWheelSpeed,
                  onChanged: (value) {
                    setState(() {
                      leftWheelSpeed = value;
                    });
                  },
                  onChangeEnd: (value) {
                    _scheduleSaveValues();
                  },
                ),
              ),
              Expanded(
                child: _buildWheelSlider(
                  title: 'Скорость правого колеса',
                  value: rightWheelSpeed,
                  onChanged: (value) {
                    setState(() {
                      rightWheelSpeed = value;
                    });
                  },
                  onChangeEnd: (value) {
                    _scheduleSaveValues();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _buildSizeSlider(
                  title: 'Размер базы',
                  value: baseSize,
                  min: 0.1,
                  max: 1.0,
                  divisions: 90,
                  digits: 2,
                  onChanged: (value) {
                    setState(() {
                      baseSize = value;
                    });
                  },
                  onChangeEnd:
                      (value) {
                    _scheduleSaveValues();
                  },
                ),
              ),
              Expanded(
                child: _buildSizeSlider(
                  title: 'Радиус колеса',
                  value: wheelRadius,
                  min: 0.01,
                  max: 0.2,
                  divisions: 19,
                  digits: 2,
                  onChanged: (value) {
                    setState(() {
                      wheelRadius = value;
                    });
                  },
                  onChangeEnd:
                      (value) {
                    _scheduleSaveValues();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPanel() {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Статус движения',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 5,
              ),
              Text(
                movementStatus, textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhysicsPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Параметры движения',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            Text(
              'Линейная скорость: '
                  '${linearSpeed.toStringAsFixed(3)} м/с',
            ),
            Text(
              'Угловая скорость: '
                  '${angularSpeed.abs().toStringAsFixed(3)} рад/с',
            ),
            Text(
              'Радиус траектории: '
                  '$turningRadiusText',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Журнал записей',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Машина времени',
                  onPressed: logRows.isEmpty
                      ? null
                      : _showTimeMachine,
                  icon: const Icon(Icons.history),
                ),
              ],
            ),
            Expanded(
              child: logRows.isEmpty
                  ? const Center(
                child: Text('Записей пока нет'),
              )
                  : Scrollbar(
                controller: logVerticalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: logVerticalController,
                  child: SingleChildScrollView(
                    controller: logHorizontalController,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(
                          label: Text(
                            'id',
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'left',
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'right',
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'base',
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'radius',
                          ),
                        ),
                      ],

                      rows: logRows.map((row) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                '${row.id}',
                              ),
                            ),
                            DataCell(
                              Text(
                                '${row.leftWheelSpeed}',
                              ),
                            ),

                            DataCell(
                              Text(
                                '${row.rightWheelSpeed}',
                              ),
                            ),

                            DataCell(
                              Text(
                                row.baseSize.toStringAsFixed(2),
                              ),
                            ),
                            DataCell(
                              Text(
                                row.wheelRadius.toStringAsFixed(2),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: CustomPaint(
                  painter: RobotPainter(
                    robotX: robotX,
                    robotY: robotY,
                    robotAngle: robotAngle,
                    trail: trail,
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 6,
            ),

            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: isRunning
                        ? _stopSimulation
                        : _startSimulation,
                    child: Text(
                      isRunning
                          ? 'Стоп'
                          : 'Старт',
                    ),
                  ),
                ),

                const SizedBox(
                  width: 6,
                ),

                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetSimulation,
                    child: const Text('Сбросить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lab 5 — WebSocket'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
            ),
            child: Center(
              child: Text(
                isConnecting
                    ? 'Подключение...'
                    : isConnected
                    ? 'WS: подключено'
                    : 'WS: нет связи',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Переподключиться',
            onPressed: isConnecting
                ? null
                : _connectToServer,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                flex: 4,
                child: _buildControls(),
              ),

              const SizedBox(
                height: 6,
              ),

              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildSimulationPanel(),
                    ),

                    const SizedBox(
                      width: 6,
                    ),

                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildStatusPanel(),
                          ),
                          Expanded(
                            flex: 2,

                            child: _buildPhysicsPanel(),
                          ),

                          Expanded(
                            flex: 4,
                            child: _buildLogPanel(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RobotPainter extends CustomPainter {
  final double robotX;
  final double robotY;
  final double robotAngle;
  final List<Offset> trail;

  static const double scale = 55;
  static const double bodySize = 40;

  RobotPainter({
    required this.robotX,
    required this.robotY,
    required this.robotAngle,
    required this.trail,
  });

  @override
  void paint(Canvas canvas, Size size,) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    if (trail.length > 1) {
      final path = Path();
      final firstPoint = Offset(
        center.dx + trail.first.dx * scale,
        center.dy + trail.first.dy * scale,
      );
      path.moveTo(
        firstPoint.dx,
        firstPoint.dy,
      );

      for (int i = 1; i < trail.length; i++) {
        final point = Offset(
          center.dx + trail[i].dx * scale,
          center.dy + trail[i].dy * scale,
        );
        path.lineTo(
          point.dx,
          point.dy,
        );
      }

      final trailPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, trailPaint);
    }

    final robotPosition =
    Offset(
      center.dx + robotX * scale,
      center.dy + robotY * scale,
    );

    canvas.save();
    canvas.translate(robotPosition.dx, robotPosition.dy);

    canvas.rotate(robotAngle);

    final body = Rect.fromCenter(
      center: Offset.zero,
      width: bodySize,
      height: bodySize,
    );

    final bodyPaint = Paint()
      ..color = Colors.blue.shade300
      ..style = PaintingStyle.fill;

    canvas.drawRect(body, bodyPaint);

    const double wheelLength = 22;
    const double wheelThickness = 7;

    final rightWheel = Rect.fromCenter(
      center: const Offset(
        0,
        bodySize / 2 + 5,
      ),
      width: wheelLength,
      height: wheelThickness,
    );

    final leftWheel = Rect.fromCenter(
      center: const Offset(
        0,
        -bodySize / 2 - 5,
      ),
      width: wheelLength,
      height: wheelThickness,
    );

    final wheelPaint = Paint()
      ..color = Colors.black;

    canvas.drawRect(rightWheel, wheelPaint,);
    canvas.drawRect(leftWheel, wheelPaint,);

    final frontPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;

    canvas.drawLine(
      const Offset(
        bodySize / 2,
        -bodySize / 4,
      ),

      const Offset(
        bodySize / 2,
        bodySize / 4,
      ),

      frontPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(RobotPainter oldDelegate) {
    return true;
  }
}
