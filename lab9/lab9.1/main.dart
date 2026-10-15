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
        colorSchemeSeed: Colors.blue
    ),
    home: const BallisticsPage(),
  );
}

class BallisticsPage extends StatefulWidget {
  const BallisticsPage({super.key});

  @override
  State<BallisticsPage> createState() => _BallisticsPageState();
}

class _BallisticsPageState extends State<BallisticsPage> with SingleTickerProviderStateMixin {
  static const double _epsilon = 0.7;
  static const double _rollingFriction = 0.035;

  late final Ticker _ticker;
  Duration? _lastTick;
  double _angle = 45;
  double _speed = 18;
  double _mass = 2;
  double _gravity = 9.8;
  double _deltaV = 2;
  double _x = 0;
  double _y = 0;
  double _vx = 0;
  double _vy = 0;
  bool _rolling = false;
  bool _finished = false;
  final List<Offset> _trail = [];

  @override
  void initState() {
    super.initState();
    _reset();
    _ticker = createTicker(_onTick)..start();
  }

  void _reset() {
    final radians = _angle * math.pi / 180;
    _x = 0;
    _y = 0;
    _vx = _speed * math.cos(radians);
    _vy = _speed * math.sin(radians);
    _rolling = false;
    _finished = false;
    _lastTick = null;
    _trail
      ..clear()
      ..add(Offset.zero);
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null || _finished) return;
    final frame = ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, 0.05,);
    final steps = math.max(1, (frame / 0.008).ceil());
    final dt = frame / steps;
    setState(() {
      for (var i = 0; i < steps; i++) {
        _advance(dt);
        if (_finished) break;
      }
      if ((_trail.last - Offset(_x, _y)).distance > 0.08) {
        _trail.add(Offset(_x, _y));
        if (_trail.length > 3000) _trail.removeAt(0);
      }
    });
  }

  void _advance(double dt) {
    if (_rolling) {
      final nextVx = math.max(0.0, _vx - _rollingFriction * _gravity * dt);
      _x += (_vx + nextVx) * 0.5 * dt;
      _vx = nextVx;
      if (_vx <= 0.02) {
        _vx = 0;
        _finished = true;
      }
      return;
    }

    _x += _vx * dt;
    _y += _vy * dt - 0.5 * _gravity * dt * dt;
    _vy -= _gravity * dt;
    if (_y <= 0 && _vy < 0) {
      final reboundSpeed = math.max(0.0, -_vy - _deltaV);
      _y = 0;
      _vx *= 0.96;
      if (reboundSpeed < _epsilon) {
        _vy = 0;
        _rolling = true;
      } else {
        _vy = reboundSpeed;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
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
            onPressed: () => setState(_reset),
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
                    angle: _angle,
                    initialSpeed: _speed,
                    gravity: _gravity,
                    x: _x,
                    y: _y,
                    trail: _trail,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _slider('Угол alpha', _angle, 5, 85, ' град.', (value) => _angle = value),
            _slider(
              'Скорость V0',
              _speed,
              4,
              32,
              ' м/с',
              (value) => _speed = value,
            ),
            _slider('Масса m', _mass, 0.2, 10, ' кг', (value) => _mass = value),
            _slider(
              'Ускорение g',
              _gravity,
              3,
              20,
              ' м/с^2',
              (value) => _gravity = value,
            ),
            _slider(
              'Потеря скорости delta V',
              _deltaV,
              0.5,
              5,
              ' м/с',
              (value) => _deltaV = value,
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String title, double value, double min, double max, String unit, ValueChanged<double> update) {
    final shown = title == 'Угол alpha'
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
            _reset();
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
        )
        .clamp(1.2, 38.0);
    final axisX = 42.0;
    final axisY = size.height - 36;
    final camera = math.max(0.0, x - (size.width - 95) / scale);
    Offset point(double px, double py) =>
        Offset(axisX + (px - camera) * scale, axisY - py * scale);

    final axisPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5;
    final tickPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    canvas.drawLine(Offset(axisX, 20), Offset(axisX, axisY), axisPaint);
    canvas.drawLine(
      Offset(axisX, axisY),
      Offset(size.width - 15, axisY),
      axisPaint,
    );
    _label(canvas, 'Y', const Offset(26, 7), 14, Colors.black87);
    _label(canvas, 'X', Offset(size.width - 18, axisY + 7), 14, Colors.black87);

    final interval = <double>[1, 2, 5, 10, 20, 50, 100, 200, 500,].firstWhere((step) => step * scale >= 55, orElse: () => 1000);
    final firstX = (camera / interval).ceil() * interval;
    for (
      var worldX = firstX;
      worldX < camera + (size.width - axisX) / scale;
      worldX += interval
    ) {
      final screenX = point(worldX, 0).dx;
      if (screenX < axisX + 8 || screenX > size.width - 25) continue;
      canvas.drawLine(
        Offset(screenX, axisY - 4),
        Offset(screenX, axisY + 4),
        axisPaint,
      );
      _label(
        canvas,
        worldX.toStringAsFixed(0),
        Offset(screenX - 6, axisY + 8),
        10,
        Colors.black54,
      );
    }
    for (var worldY = interval; worldY * scale < axisY - 25; worldY += interval) {
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
      _label(
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
      canvas.drawPath(path, Paint()
          ..color = Colors.blue.shade300
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.drawCircle(point(x, y), 9, Paint()..color = Colors.blue);
    canvas.restore();
  }

  void _label(
    Canvas canvas,
    String value,
    Offset position,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant FlightPainter oldDelegate) => true;
}
