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
      title: 'Бутылка',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const BottlePage(),
    );
  }
}

class BottlePage extends StatefulWidget {
  const BottlePage({super.key});

  @override
  State<BottlePage> createState() => _BottlePageState();
}

class _BottlePageState extends State<BottlePage>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  int h = 210;
  int d = 120;
  int k = 60;

  double fromH = 210;
  double fromD = 120;
  double fromK = 60;

  double toH = 210;
  double toD = 120;
  double toK = 60;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
  }

  double animatedValue(double from, double to) {
    final t = Curves.easeInOut.transform(controller.value);
    return from + (to - from) * t;
  }

  void changeParameters({
    int? newH,
    int? newD,
    int? newK,
  }) {
    final currentH = animatedValue(fromH, toH);
    final currentD = animatedValue(fromD, toD);
    final currentK = animatedValue(fromK, toK);

    setState(() {
      if (newH != null) {
        h = newH;
      }

      if (newD != null) {
        d = newD;
      }

      if (newK != null) {
        k = newK;
      }

      fromH = currentH;
      fromD = currentD;
      fromK = currentK;

      toH = h.toDouble();
      toD = d.toDouble();
      toK = k.toDouble();
    });

    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget parameterSlider({
    required String name,
    required int value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: '$value',
          onChanged: (value) {
            onChanged(value.round());
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Бутылка'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                height: 350,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    final animatedH = animatedValue(fromH, toH);
                    final animatedD = animatedValue(fromD, toD);
                    final animatedK = animatedValue(fromK, toK);

                    return CustomPaint(
                      painter: BottlePainter(
                        h: animatedH,
                        d: animatedD,
                        k: animatedK,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 15),

              parameterSlider(
                name: 'Высота h',
                value: h,
                min: 90,
                max: 300,
                divisions: 70,
                onChanged: (value) {
                  changeParameters(newH: value);
                },
              ),

              parameterSlider(
                name: 'Диаметр d',
                value: d,
                min: 30,
                max: 180,
                divisions: 50,
                onChanged: (value) {
                  changeParameters(newD: value);
                },
              ),

              parameterSlider(
                name: 'Заполнение k, %',
                value: k,
                min: 0,
                max: 100,
                divisions: 100,
                onChanged: (value) {
                  changeParameters(newK: value);
                },
              ),

              const SizedBox(height: 10),

              Text(
                'Горлышко: высота ${h ~/ 3}, диаметр ${d ~/ 3}',
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BottlePainter extends CustomPainter {
  final double h;
  final double d;
  final double k;

  BottlePainter({
    required this.h,
    required this.d,
    required this.k,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    final top = (size.height - h) / 2;
    final bottom = top + h;

    final left = centerX - d / 2;
    final right = centerX + d / 2;

    final neckHeight = h / 3;
    final neckWidth = d / 3;

    final neckLeft = centerX - neckWidth / 2;
    final neckRight = centerX + neckWidth / 2;

    final shoulderStart = top + neckHeight;
    final shoulderHeight = h * 0.10;
    final shoulderEnd = shoulderStart + shoulderHeight;

    final bottomRadius = math.min(14.0, d * 0.10);

    final bottlePath = Path();

    bottlePath.moveTo(neckLeft, top);

    bottlePath.lineTo(neckRight, top);

    bottlePath.lineTo(
      neckRight,
      shoulderStart,
    );

    bottlePath.cubicTo(
      neckRight,
      shoulderStart + shoulderHeight * 0.5,
      right,
      shoulderStart + shoulderHeight * 0.3,
      right,
      shoulderEnd,
    );

    bottlePath.lineTo(
      right,
      bottom - bottomRadius,
    );

    bottlePath.quadraticBezierTo(
      right,
      bottom,
      right - bottomRadius,
      bottom,
    );

    bottlePath.lineTo(
      left + bottomRadius,
      bottom,
    );

    bottlePath.quadraticBezierTo(
      left,
      bottom,
      left,
      bottom - bottomRadius,
    );

    bottlePath.lineTo(
      left,
      shoulderEnd,
    );

    bottlePath.cubicTo(
      left,
      shoulderStart + shoulderHeight * 0.3,
      neckLeft,
      shoulderStart + shoulderHeight * 0.5,
      neckLeft,
      shoulderStart,
    );

    bottlePath.close();

    final backgroundPaint = Paint()
      ..color = Colors.white;

    canvas.drawPath(
      bottlePath,
      backgroundPaint,
    );

    if (k > 0) {
      final liquidTop = bottom - h * (k / 100);

      final liquidPaint = Paint()
        ..color = Colors.lightBlue;

      canvas.save();

      canvas.clipPath(bottlePath);

      canvas.drawRect(
        Rect.fromLTRB(
          left,
          liquidTop,
          right,
          bottom,
        ),
        liquidPaint,
      );

      final surfacePaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(left, liquidTop),
        Offset(right, liquidTop),
        surfacePaint,
      );

      canvas.restore();
    }

    final outlinePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      bottlePath,
      outlinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant BottlePainter oldDelegate) {
    return oldDelegate.h != h ||
        oldDelegate.d != d ||
        oldDelegate.k != k;
  }
}
