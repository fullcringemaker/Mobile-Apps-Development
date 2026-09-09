import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  State<WheelControllerPage> createState() => _WheelControllerPageState();
}

class _WheelControllerPageState extends State<WheelControllerPage> {
  static const String board = 'wheelbeh';
  static const String leftVariable = 'leftwheelspeed';
  static const String rightVariable = 'rightwheelspeed';

  int leftWheelSpeed = 0;
  int rightWheelSpeed = 0;

  @override
  void initState() {
    super.initState();
    _loadWheelSpeeds();
  }

  Future<int> _readWheelSpeed(String variable) async {
    final url = Uri.parse(
      'https://iocontrol.ru/api/readData/$board/$variable',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['check'] == true) {
        final value = int.tryParse(data['value'].toString()) ?? 0;
        return value.clamp(-10, 10).toInt();
      }
    }

    return 0;
  }

  Future<void> _loadWheelSpeeds() async {
    final values = await Future.wait([
      _readWheelSpeed(leftVariable),
      _readWheelSpeed(rightVariable),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      leftWheelSpeed = values[0];
      rightWheelSpeed = values[1];
    });
  }

  Future<void> _sendWheelSpeed(String variable, int value) async {
    final url = Uri.parse(
      'https://iocontrol.ru/api/sendData/$board/$variable/$value',
    );

    await http.get(url);
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

    final totalSpeed = leftWheelSpeed + rightWheelSpeed;

    if (totalSpeed > 0) {
      if (rightWheelSpeed > leftWheelSpeed) {
        return 'Поворот влево';
      }
      return 'Поворот вправо';
    }

    if (totalSpeed < 0) {
      if (rightWheelSpeed < leftWheelSpeed) {
        return 'Поворот влево';
      }
      return 'Поворот вправо';
    }

    if (rightWheelSpeed > leftWheelSpeed) {
      return 'Поворот влево';
    }
    return 'Поворот вправо';
  }

  Widget _buildWheelSlider({
    required String title,
    required int value,
    required ValueChanged<int> onChanged,
    required ValueChanged<int> onChangeEnd,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            Slider(
              value: value.toDouble(),
              min: -10,
              max: 10,
              divisions: 20,
              label: value.toString(),
              onChanged: (newValue) {
                onChanged(newValue.round());
              },
              onChangeEnd: (newValue) {
                onChangeEnd(newValue.round());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление объектом'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildWheelSlider(
                title: 'Скорость левого колеса',
                value: leftWheelSpeed,
                onChanged: (value) {
                  setState(() {
                    leftWheelSpeed = value;
                  });
                },
                onChangeEnd: (value) {
                  _sendWheelSpeed(leftVariable, value);
                },
              ),
              _buildWheelSlider(
                title: 'Скорость правого колеса',
                value: rightWheelSpeed,
                onChanged: (value) {
                  setState(() {
                    rightWheelSpeed = value;
                  });
                },
                onChangeEnd: (value) {
                  _sendWheelSpeed(rightVariable, value);
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'Статус движения',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Text(
                  movementStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
