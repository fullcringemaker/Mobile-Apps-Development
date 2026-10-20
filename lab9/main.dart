  import 'dart:math' as math;

  import 'package:flutter/material.dart';
  import 'package:flutter/scheduler.dart';

  void main() => runApp(const BallisticsApp());

  class BallisticsApp extends StatelessWidget {
    const BallisticsApp({super.key});

    @override
    Widget build(BuildContext context) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Движение тела',
      theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue),
      home: const BallisticsPage(),
    );
  }

  class BallisticsPage extends StatefulWidget {
    const BallisticsPage({super.key});

    @override
    State<BallisticsPage> createState() => SimState();
  }

  class SimState extends State<BallisticsPage> {
    static const double epsilon = 0.7;
    static const double friction = 0.035;

    late final Ticker ticker;
    Duration? lastTick;
    double angle = 45;
    double speed = 18;
    double mass = 2;
    double gravity = 9.8;
    double deltaV = 2;
    double x = 0;
    double y = 0;
    double vx = 0;
    double vy = 0;
    bool rolling = false;
    bool finished = false;
    final List<Offset> trail = [];

    @override
    void initState() {
      super.initState();
      reset();
      ticker = Ticker(tick);
      ticker.start();
    }

    void reset() {
      final radians = angle * math.pi / 180;
      x = 0;
      y = 0;
      vx = speed * math.cos(radians);
      vy = speed * math.sin(radians);
      rolling = false;
      finished = false;
      lastTick = null;
      trail.clear();
      trail.add(Offset.zero);
    }

    void tick(Duration elapsed) {
      final previous = lastTick;
      lastTick = elapsed;
      if (previous == null || finished) return;
      final frame = ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, 0.05);
      final steps = math.max(1, (frame / 0.008).ceil());
      final dt = frame / steps;
      setState(() {
        for (var i = 0; i < steps; i = i + 1) {
          step(dt);
          if (finished) break;
        }
        if ((trail.last - Offset(x, y)).distance > 0.08) {
          trail.add(Offset(x, y));
          if (trail.length > 3000) trail.removeAt(0);
        }
      });
    }

    void step(double dt) {
      if (rolling) {
        final nextVx = math.max(0.0, vx - friction * gravity * dt);
        x = x + (vx + nextVx) * 0.5 * dt;
        vx = nextVx;
        if (vx <= 0.02) {
          vx = 0;
          finished = true;
        }
        return;
      }
      x = x + vx * dt;
      y = y + vy * dt - 0.5 * gravity * dt * dt;
      vy = vy - gravity * dt;
      if (y <= 0 && vy < 0) {
        final reboundSpeed = math.max(0.0, -vy - deltaV);
        y = 0;
        vx = vx * 0.96;
        if (reboundSpeed < epsilon) {
          vy = 0;
          rolling = true;
        } else {
          vy = reboundSpeed;
        }
      }
    }

    @override
    void dispose() {
      ticker.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Движение тела'),
          actions: [
            TextButton(
              onPressed: () => setState(reset),
              child: const Text('Начать заново'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: math.min(340, math.max(230, screenHeight * 0.4)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                  ),
                  child: CustomPaint(
                    painter: FlightPainter(
                      angle: angle,
                      initialSpeed: speed,
                      gravity: gravity,
                      x: x,
                      y: y,
                      trail: trail,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              slider('Угол (alpha)', angle, 5, 85, ' град.', (value) => angle = value),
              slider('Скорость (V0)', speed, 4, 32, ' м/с', (value) => speed = value),
              slider('Масса (m)', mass, 0.2, 10, ' кг', (value) => mass = value),
              slider('Ускорение (g)', gravity, 3, 20, ' м/с^2', (value) => gravity = value),
              slider('Потеря скорости (delta V)', deltaV, 0.5, 5, ' м/с', (value) => deltaV = value),
            ],
          ),
        ),
      );
    }

    Widget slider(String title, double value, double min, double max, String unit, ValueChanged<double> update) {
      final shown = title == 'Угол (alpha)'
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1);
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              Text('$shown$unit'),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: (next) => setState(() {
              update(next);
              reset();
            }),
          ),
        ],
      );
    }
  }

  class FlightPainter extends CustomPainter {
    const FlightPainter({
      required this.angle,
      required this.initialSpeed,
      required this.gravity,
      required this.x,
      required this.y,
      required this.trail,
    });

    final double angle;
    final double initialSpeed;
    final double gravity;
    final double x;
    final double y;
    final List<Offset> trail;

    @override
    void paint(Canvas canvas, Size size) {
      final radians = angle * math.pi / 180;
      final initialVx = initialSpeed * math.cos(radians);
      final initialVy = initialSpeed * math.sin(radians);
      final apex = initialVy * initialVy / (2 * gravity);
      final range = 2 * initialVx * initialVy / gravity;
      final scale = math.min(
            (size.width - 90) / math.max(range * 1.12, 4),
            (size.height - 75) / math.max(apex * 1.25, 1.5),
          ).clamp(1.2, 38.0);
      final axisX = 42.0;
      final axisY = size.height - 36;
      final camera = math.max(0.0, x - (size.width - 95) / scale);
      Offset point(double px, double py) => Offset(axisX + (px - camera) * scale, axisY - py * scale);

      final axisPaint = Paint();
      axisPaint.color = Colors.black87;
      axisPaint.strokeWidth = 1.5;
      final tickPaint = Paint();
      tickPaint.color = Colors.black26;
      tickPaint.strokeWidth = 1;
      canvas.drawLine(Offset(axisX, 20), Offset(axisX, axisY), axisPaint);
      canvas.drawLine(
        Offset(axisX, axisY),
        Offset(size.width - 15, axisY),
        axisPaint,
      );
      label(canvas, 'Y', const Offset(26, 7), 14, Colors.black87);
      label(canvas, 'X', Offset(size.width - 18, axisY + 7), 14, Colors.black87);

      final interval = <double>[1, 2, 5, 10, 20, 50, 100, 200, 500].firstWhere((step) => step * scale >= 55, orElse: () => 1000);
      final firstX = (camera / interval).ceil() * interval;
      for (var worldX = firstX; worldX < camera + (size.width - axisX) / scale; worldX = worldX + interval) {
        final screenX = point(worldX, 0).dx;
        if (screenX < axisX + 8 || screenX > size.width - 25) continue;
        canvas.drawLine(
          Offset(screenX, axisY - 4),
          Offset(screenX, axisY + 4),
          axisPaint,
        );
        label(
          canvas,
          worldX.toStringAsFixed(0),
          Offset(screenX - 6, axisY + 8),
          10,
          Colors.black54,
        );
      }
      for (var worldY = interval; worldY * scale < axisY - 25; worldY = worldY + interval) {
        final screenY = axisY - worldY * scale;
        canvas.drawLine(
          Offset(axisX - 4, screenY),
          Offset(axisX + 4, screenY),
          axisPaint,
        );
        canvas.drawLine(
          Offset(axisX + 5, screenY),
          Offset(size.width - 15, screenY),
          tickPaint,
        );
        label(
          canvas,
          worldY.toStringAsFixed(0),
          Offset(5, screenY - 6),
          10,
          Colors.black54,
        );
      }

      canvas.save();
      canvas.clipRect(Rect.fromLTRB(axisX, 18, size.width - 15, axisY + 10));
      if (trail.length > 1) {
        final path = Path();
        final start = point(trail.first.dx, trail.first.dy);
        path.moveTo(start.dx, start.dy);
        for (final sample in trail.skip(1)) {
          final p = point(sample.dx, sample.dy);
          path.lineTo(p.dx, p.dy);
        }
        final pathPaint = Paint();
        pathPaint.color = Colors.blue.shade300;
        pathPaint.style = PaintingStyle.stroke;
        pathPaint.strokeWidth = 2;
        canvas.drawPath(path, pathPaint);
      }
      final ballPaint = Paint();
      ballPaint.color = Colors.blue;
      canvas.drawCircle(point(x, y), 9, ballPaint);
      canvas.restore();
    }

    void label(Canvas canvas, String value, Offset position, double size, Color color) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(color: color, fontSize: size),
        ),
        textDirection: TextDirection.ltr,
      );
      painter.layout();
      painter.paint(canvas, position);
    }

    @override
    bool shouldRepaint(covariant FlightPainter oldDelegate) => true;
  }
