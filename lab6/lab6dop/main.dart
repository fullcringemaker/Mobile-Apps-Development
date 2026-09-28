import 'package:flutter/material.dart';
import 'package:ditredi/ditredi.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  runApp(const MyApp());
}

class StepPoint {
  final double x;
  final double y;
  final double z;

  StepPoint(this.x, this.y, this.z);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const OptimizationPage(),
    );
  }
}

class OptimizationPage extends StatefulWidget {
  const OptimizationPage({super.key});

  @override
  State<OptimizationPage> createState() => _OptimizationPageState();
}

class _OptimizationPageState extends State<OptimizationPage> {
  double x0 = 2.0;
  double y0 = 2.0;

  double a = 1.0;
  double b = 1.0;

  double h = 0.25;
  double eps = 0.01;

  final double visualScaleZ = 0.05;

  final List<StepPoint> path = [];

  late DiTreDiController controller;

  @override
  void initState() {
    super.initState();

    controller = DiTreDiController(
      rotationX: -20,
      rotationY: 35,
      userScale: 1.0,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  double f(double x, double y) {
    return a * x * x + b * y * y;
  }

  double visualZ(double value) {
    return value * visualScaleZ;
  }

  void runOptimization() {
    final List<StepPoint> newPath = [];

    double x = x0;
    double y = y0;
    double currentF = f(x, y);

    newPath.add(StepPoint(x, y, currentF));

    for (int i = 0; i < 1000; i++) {
      final allNeighbours = [
        StepPoint(x + h, y, f(x + h, y)),
        StepPoint(x - h, y, f(x - h, y)),
        StepPoint(x, y + h, f(x, y + h)),
        StepPoint(x, y - h, f(x, y - h)),
      ];

      final neighbours = allNeighbours.where((point) {
        return point.x >= -5 &&
            point.x <= 5 &&
            point.y >= -5 &&
            point.y <= 5;
      }).toList();

      if (neighbours.isEmpty) {
        break;
      }

      StepPoint best = neighbours[0];

      for (final point in neighbours) {
        if (point.z < best.z) {
          best = point;
        }
      }

      if (best.z >= currentF) {
        break;
      }

      final difference = (currentF - best.z).abs();

      x = best.x;
      y = best.y;
      currentF = best.z;

      newPath.add(best);

      if (difference < eps) {
        break;
      }
    }

    setState(() {
      path
        ..clear()
        ..addAll(newPath);
    });
  }

  void clearPath() {
    path.clear();
  }

  List<Line3D> createAxes() {
    final List<Line3D> lines = [];

    const double axisLength = 7.0;
    const double arrow = 0.45;

    lines.addAll([
      Line3D(
        Vector3(-axisLength, 0, 0),
        Vector3(axisLength, 0, 0),
        width: 3,
        color: Colors.red,
      ),
      Line3D(
        Vector3(0, 0, -axisLength),
        Vector3(0, 0, axisLength),
        width: 3,
        color: Colors.blue,
      ),
      Line3D(
        Vector3(0, -14, 0),
        Vector3(0, 14, 0),
        width: 3,
        color: Colors.green,
      ),
    ]);

    lines.addAll([
      Line3D(
        Vector3(axisLength - arrow, 0.25, 0),
        Vector3(axisLength, 0, 0),
        width: 3,
        color: Colors.red,
      ),
      Line3D(
        Vector3(axisLength - arrow, -0.25, 0),
        Vector3(axisLength, 0, 0),
        width: 3,
        color: Colors.red,
      ),
    ]);

    lines.addAll([
      Line3D(
        Vector3(0.25, 0, axisLength - arrow),
        Vector3(0, 0, axisLength),
        width: 3,
        color: Colors.blue,
      ),
      Line3D(
        Vector3(-0.25, 0, axisLength - arrow),
        Vector3(0, 0, axisLength),
        width: 3,
        color: Colors.blue,
      ),
    ]);

    lines.addAll([
      Line3D(
        Vector3(0.25, 14 - arrow, 0),
        Vector3(0, 14, 0),
        width: 3,
        color: Colors.green,
      ),
      Line3D(
        Vector3(-0.25, 14 - arrow, 0),
        Vector3(0, 14, 0),
        width: 3,
        color: Colors.green,
      ),
    ]);

    lines.addAll(createXLabel());
    lines.addAll(createYLabel());
    lines.addAll(createZLabel());

    return lines;
  }

  List<Line3D> createXLabel() {
    const color = Colors.red;

    return [
      Line3D(
        Vector3(7.3, -0.35, 0),
        Vector3(7.9, 0.35, 0),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(7.3, 0.35, 0),
        Vector3(7.9, -0.35, 0),
        width: 4,
        color: color,
      ),
    ];
  }

  List<Line3D> createYLabel() {
    const color = Colors.blue;

    return [
      Line3D(
        Vector3(-0.3, 0.35, 7.3),
        Vector3(0, 0, 7.6),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(0.3, 0.35, 7.3),
        Vector3(0, 0, 7.6),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(0, 0, 7.6),
        Vector3(0, -0.4, 7.9),
        width: 4,
        color: color,
      ),
    ];
  }

  List<Line3D> createZLabel() {
    const color = Colors.green;

    return [
      Line3D(
        Vector3(-0.35, 14.7, 0),
        Vector3(0.35, 14.7, 0),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(0.35, 14.7, 0),
        Vector3(-0.35, 14.1, 0),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(-0.35, 14.1, 0),
        Vector3(0.35, 14.1, 0),
        width: 4,
        color: color,
      ),
    ];
  }

  List<Line3D> createParaboloid() {
    final List<Line3D> lines = [];

    const double min = -5;
    const double max = 5;
    const double step = 0.4;

    const color = Color.fromARGB(150, 70, 120, 220);

    for (double x = min; x <= max; x += step) {
      for (double y = min; y < max; y += step) {
        lines.add(
          Line3D(
            Vector3(
              x,
              visualZ(f(x, y)),
              y,
            ),
            Vector3(
              x,
              visualZ(f(x, y + step)),
              y + step,
            ),
            width: 1,
            color: color,
          ),
        );
      }
    }

    for (double y = min; y <= max; y += step) {
      for (double x = min; x < max; x += step) {
        lines.add(
          Line3D(
            Vector3(
              x,
              visualZ(f(x, y)),
              y,
            ),
            Vector3(
              x + step,
              visualZ(f(x + step, y)),
              y,
            ),
            width: 1,
            color: color,
          ),
        );
      }
    }

    return lines;
  }

  List<Line3D> createPathLines() {
    final List<Line3D> lines = [];

    for (int i = 0; i < path.length - 1; i++) {
      final current = path[i];
      final next = path[i + 1];

      lines.add(
        Line3D(
          Vector3(
            current.x,
            visualZ(current.z) + 0.05,
            current.y,
          ),
          Vector3(
            next.x,
            visualZ(next.z) + 0.05,
            next.y,
          ),
          width: 3,
          color: Colors.red,
        ),
      );
    }

    return lines;
  }

  List<Point3D> createPathPoints() {
    final List<Point3D> points = [];

    if (path.isEmpty) {
      return points;
    }

    for (int i = 0; i < path.length - 1; i++) {
      final point = path[i];

      points.add(
        Point3D(
          Vector3(
            point.x,
            visualZ(point.z) + 0.05,
            point.y,
          ),
          width: 12,
          color: Colors.red,
        ),
      );
    }

    final last = path.last;

    points.add(
      Point3D(
        Vector3(
          last.x,
          visualZ(last.z) + 0.05,
          last.y,
        ),
        width: 16,
        color: Colors.green,
      ),
    );

    return points;
  }

  Widget slider({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required int digits,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value.toStringAsFixed(digits),
              ),
            ],
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск минимума'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              child: DiTreDiDraggable(
                controller: controller,
                child: DiTreDi(
                  controller: controller,
                  figures: [
                    ...createParaboloid(),
                    ...createAxes(),
                    ...createPathLines(),
                    ...createPathPoints(),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(
              top: 10,
              bottom: 8,
            ),
            child: Text(
              'f(x, y) = ax² + by²',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  slider(
                    title: 'a',
                    value: a,
                    min: -5,
                    max: 5,
                    divisions: 100,
                    digits: 1,
                    onChanged: (value) {
                      setState(() {
                        a = value;
                        clearPath();
                      });
                    },
                  ),
                  slider(
                    title: 'b',
                    value: b,
                    min: -5,
                    max: 5,
                    divisions: 100,
                    digits: 1,
                    onChanged: (value) {
                      setState(() {
                        b = value;
                        clearPath();
                      });
                    },
                  ),
                  slider(
                    title: 'x0',
                    value: x0,
                    min: -5,
                    max: 5,
                    divisions: 100,
                    digits: 1,
                    onChanged: (value) {
                      setState(() {
                        x0 = value;
                        clearPath();
                      });
                    },
                  ),
                  slider(
                    title: 'y0',
                    value: y0,
                    min: -5,
                    max: 5,
                    divisions: 100,
                    digits: 1,
                    onChanged: (value) {
                      setState(() {
                        y0 = value;
                        clearPath();
                      });
                    },
                  ),
                  slider(
                    title: 'h',
                    value: h,
                    min: 0.1,
                    max: 1.0,
                    divisions: 18,
                    digits: 2,
                    onChanged: (value) {
                      setState(() {
                        h = value;
                        clearPath();
                      });
                    },
                  ),
                  slider(
                    title: 'eps',
                    value: eps,
                    min: 0.001,
                    max: 0.1,
                    divisions: 99,
                    digits: 3,
                    onChanged: (value) {
                      setState(() {
                        eps = value;
                        clearPath();
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      5,
                      16,
                      16,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: runOptimization,
                        child: const Text(
                          'Запустить',
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
