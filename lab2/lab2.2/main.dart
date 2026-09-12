import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mysql1/mysql1.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
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

class WheelControllerPage extends StatefulWidget {
  const WheelControllerPage({super.key});

  @override
  State<WheelControllerPage> createState() {
    return _WheelControllerPageState();
  }
}

class _WheelControllerPageState extends State<WheelControllerPage> {
  static const String dbHost = 'students.yss.su';
  static const int dbPort = 3306;
  static const String dbUser = 'iu9mobile';
  static const String dbPassword = 'bmstubmstu123';
  static const String dbName = 'iu9mobile';

  int leftWheelSpeed = 0;
  int rightWheelSpeed = 0;

  double baseSize = 0.4;
  double wheelRadius = 0.05;

  double robotX = 0;
  double robotY = 0;
  double robotAngle = math.pi / 2;

  bool isRunning = false;

  Timer? timer;

  final List<Offset> trail = [
    Offset.zero,
  ];

  static const double timeStep = 0.04;

  @override
  void initState() {
    super.initState();

    _loadValues();
  }

  @override
  void dispose() {
    timer?.cancel();

    super.dispose();
  }

  Future<MySqlConnection> _openConnection() async {
    final settings = ConnectionSettings(
      host: dbHost,
      port: dbPort,
      user: dbUser,
      password: dbPassword,
      db: dbName,
    );

    final connection = await MySqlConnection.connect(
      settings,
    );

    return connection;
  }

  Future<void> _loadValues() async {
    MySqlConnection? connection;

    try {
      connection = await _openConnection();

      final result = await connection.query(
        '''
        SELECT
          id,
          leftwheelspeed,
          rightwheelspeed,
          basesize,
          wheelradius
        FROM testirovochka
        ORDER BY id DESC
        LIMIT 1
        ''',
      );

      if (result.isEmpty) {
        await connection.query(
          '''
          INSERT INTO testirovochka
          (
            leftwheelspeed,
            rightwheelspeed,
            basesize,
            wheelradius
          )
          VALUES (?, ?, ?, ?)
          ''',
          [
            leftWheelSpeed,
            rightWheelSpeed,
            baseSize,
            wheelRadius,
          ],
        );

        debugPrint('Первая запись создана в MySQL');

        return;
      }

      final row = result.first;

      final loadedLeftWheelSpeed = (row['leftwheelspeed'] as num).toInt();
      final loadedRightWheelSpeed = (row['rightwheelspeed'] as num).toInt();
      final loadedBaseSize = (row['basesize'] as num).toDouble();
      final loadedWheelRadius = (row['wheelradius'] as num).toDouble();

      if (!mounted) {
        return;
      }

      setState(() {
        leftWheelSpeed = loadedLeftWheelSpeed;
        rightWheelSpeed = loadedRightWheelSpeed;
        baseSize = loadedBaseSize.clamp(0.1, 1.0).toDouble();
        wheelRadius = loadedWheelRadius.clamp(0.01, 0.2).toDouble();
      });

      debugPrint('Последние значения загружены из MySQL');
    } catch (_) {
      return;
    } finally {
      if (connection != null) {
        await connection.close();
      }
    }
  }

  Future<void> _saveValues() async {
    MySqlConnection? connection;

    try {
      connection = await _openConnection();

      await connection.query(
        '''
        INSERT INTO testirovochka
        (
          leftwheelspeed,
          rightwheelspeed,
          basesize,
          wheelradius
        )
        VALUES (?, ?, ?, ?)
        ''',
        [
          leftWheelSpeed,
          rightWheelSpeed,
          baseSize,
          wheelRadius,
        ],
      );

      debugPrint('Новая запись добавлена в MySQL');
    } catch (_) {
      return;
    } finally {
      if (connection != null) {
        await connection.close();
      }
    }
  }

  double get leftLinearSpeed {
    return leftWheelSpeed * wheelRadius;
  }

  double get rightLinearSpeed {
    return rightWheelSpeed * wheelRadius;
  }

  double get linearSpeed {
    return (
        leftLinearSpeed +
            rightLinearSpeed
    ) / 2;
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
      const Duration(milliseconds: 40),
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 2,
            ),
            Text(
              '$value рад/с',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              height: 32,
              child: Slider(
                value: value.toDouble(),
                min: -10,
                max: 10,
                divisions: 20,
                onChanged: (newValue) {
                  onChanged(
                    newValue.toInt(),
                  );
                },
                onChangeEnd: (newValue) {
                  onChangeEnd(
                    newValue.toInt(),
                  );
                },
              ),
            ),
            const Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '-10',
                  style: TextStyle(
                    fontSize: 10,
                  ),
                ),
                Text(
                  '0',
                  style: TextStyle(
                    fontSize: 10,
                  ),
                ),
                Text(
                  '10',
                  style: TextStyle(
                    fontSize: 10,
                  ),
                ),
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 2,
            ),
            Text(
              '${value.toStringAsFixed(digits)} м',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              height: 32,
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min.toStringAsFixed(
                    digits,
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                  ),
                ),
                Text(
                  max.toStringAsFixed(
                    digits,
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                  ),
                ),
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
                  title:
                  'Скорость левого колеса',
                  value: leftWheelSpeed,
                  onChanged: (value) {
                    setState(() {
                      leftWheelSpeed = value;
                    });
                  },
                  onChangeEnd: (value) {
                    _saveValues();
                  },
                ),
              ),
              const SizedBox(
                height: 6,
              ),
              Expanded(
                child: _buildWheelSlider(
                  title:
                  'Скорость правого колеса',
                  value: rightWheelSpeed,
                  onChanged: (value) {
                    setState(() {
                      rightWheelSpeed = value;
                    });
                  },
                  onChangeEnd: (value) {
                    _saveValues();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(
          width: 6,
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
                  onChangeEnd: (value) {
                    _saveValues();
                  },
                ),
              ),
              const SizedBox(
                height: 6,
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
                  onChangeEnd: (value) {
                    _saveValues();
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
      margin: EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(
            10,
          ),
          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              const Text(
                'Статус движения',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                movementStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhysicsRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(
            width: 4,
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhysicsPanel() {
    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(
            10,
          ),
          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              const Text(
                'Параметры движения',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              _buildPhysicsRow(
                'Линейная скорость',
                '${linearSpeed.toStringAsFixed(3)} м/с',
              ),
              _buildPhysicsRow(
                'Угловая скорость',
                '${angularSpeed.abs().toStringAsFixed(3)} рад/с',
              ),
              _buildPhysicsRow(
                'Радиус траектории',
                turningRadiusText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimulationPanel() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(
          8,
        ),
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
                  borderRadius:
                  BorderRadius.circular(
                    10,
                  ),
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
                  child: SizedBox(
                    height: 36,
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
                ),
                const SizedBox(
                  width: 6,
                ),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed:
                      _resetSimulation,
                      child: const Text(
                        'Сбросить',
                      ),
                    ),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(
            8,
          ),
          child: Column(
            children: [
              Expanded(
                flex: 4,
                child: _buildControls(),
              ),
              const SizedBox(
                height: 8,
              ),
              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child:
                      _buildSimulationPanel(),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            flex: 2,
                            child:
                            _buildStatusPanel(),
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          Expanded(
                            flex: 4,
                            child:
                            _buildPhysicsPanel(),
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
  void paint(Canvas canvas, Size size) {
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

      final trailPaint = Paint();

      trailPaint.color = Colors.blue;
      trailPaint.strokeWidth = 2;
      trailPaint.style = PaintingStyle.stroke;

      canvas.drawPath(path, trailPaint);
    }

    final robotPosition = Offset(
      center.dx + robotX * scale,
      center.dy + robotY * scale,
    );

    canvas.save();

    canvas.translate(
      robotPosition.dx,
      robotPosition.dy,
    );

    canvas.rotate(robotAngle);

    final body = Rect.fromCenter(
      center: Offset.zero,
      width: bodySize,
      height: bodySize,
    );

    final bodyPaint = Paint();

    bodyPaint.color = Colors.blue.shade300;
    bodyPaint.style = PaintingStyle.fill;

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

    final wheelPaint = Paint();

    wheelPaint.color = Colors.black;

    canvas.drawRect(rightWheel, wheelPaint);

    canvas.drawRect(leftWheel, wheelPaint);

    final frontLinePaint = Paint();
    frontLinePaint.color = Colors.white;
    frontLinePaint.strokeWidth = 3;

    canvas.drawLine(
      const Offset(
        bodySize / 2,
        -bodySize / 4,
      ),
      const Offset(
        bodySize / 2,
        bodySize / 4,
      ),
      frontLinePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(
      RobotPainter oldDelegate,
      ) {
    return true;
  }
}
