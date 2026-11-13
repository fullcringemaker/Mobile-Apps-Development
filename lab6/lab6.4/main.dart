import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ditredi/ditredi.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  runApp(const MyApp());
}

enum SurfaceFunction {
  rastrigin,
  rosenbrock,
  schafferN2,
}

class StepPoint {
  final double x;
  final double y;
  final double z;

  StepPoint(this.x, this.y, this.z);
}

class SurfaceStats {
  final double minZ;
  final double maxZ;

  const SurfaceStats(this.minZ, this.maxZ);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
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
  SurfaceFunction selectedFunction = SurfaceFunction.rastrigin;

  double x0 = 2.0;
  double y0 = 2.0;
  double h = 0.25;
  double eps = 0.01;

  double rastriginA = 10.0;
  double rosenbrockA = 1.0;
  double rosenbrockB = 100.0;

  double levelT = 0.35;

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
    switch (selectedFunction) {
      case SurfaceFunction.rastrigin:
        return 2.0 * rastriginA + (x * x - rastriginA * math.cos(2.0 * math.pi * x)) +
            (y * y - rastriginA * math.cos(2.0 * math.pi * y));

      case SurfaceFunction.rosenbrock:
        final double first = rosenbrockA - x;
        final double second = y - x * x;

        return first * first + rosenbrockB * second * second;

      case SurfaceFunction.schafferN2:
        final double sinValue = math.sin(x * x - y * y);
        final double numerator = sinValue * sinValue - 0.5;
        final double base = 1.0 + 0.001 * (x * x + y * y);
        final double denominator = base * base;
        return 0.5 + numerator / denominator;
    }
  }

  double visualZ(double value) {
    switch (selectedFunction) {
      case SurfaceFunction.rastrigin:
        return value * 0.08;

      case SurfaceFunction.rosenbrock:
        return value * 0.0003;

      case SurfaceFunction.schafferN2:
        return value * 8.0;
    }
  }

  String get functionName {
    switch (selectedFunction) {
      case SurfaceFunction.rastrigin:
        return 'Функция Растригина';

      case SurfaceFunction.rosenbrock:
        return 'Функция Розенброка';

      case SurfaceFunction.schafferN2:
        return 'Функция Шаффера N2';
    }
  }

  String get formulaText {
    switch (selectedFunction) {
      case SurfaceFunction.rastrigin:
        return 'f(x, y) = 2A + (x^2 - A cos(2pix)) + (y^2 - A cos(2piy))';

      case SurfaceFunction.rosenbrock:
        return 'f(x, y) = (a - x)^2 + b(y - x^2)^2';

      case SurfaceFunction.schafferN2:
        return 'f(x, y) = 0.5 + (sin^2(x^2 - y^2) - 0.5) / (1 + 0.001(x^2 + y^2))^2';
    }
  }

  double get xyLimit => 5.0;

  void runOptimization() {
    final List<StepPoint> newPath = [];

    double x = x0;
    double y = y0;
    double currentF = f(x, y);

    newPath.add(
      StepPoint(x, y, currentF),
    );

    for (int i = 0; i < 1000; i++) {
      final allNeighbours = [
        StepPoint(x + h, y, f(x + h, y)),
        StepPoint(x - h, y, f(x - h, y)),
        StepPoint(x, y + h, f(x, y + h)),
        StepPoint(x, y - h, f(x, y - h)),
      ];

      final neighbours = allNeighbours.where((point) {
        return point.x >= -xyLimit && point.x <= xyLimit &&
            point.y >= -xyLimit && point.y <= xyLimit;
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

  SurfaceStats getSurfaceStats() {
    const double min = -5;
    const double max = 5;
    const double step = 0.4;

    double minZ = double.infinity;
    double maxZ = -double.infinity;

    for (double x = min; x <= max; x += step) {
      for (double y = min; y <= max; y += step) {
        final double z = f(x, y);

        if (z < minZ) {
          minZ = z;
        }
        if (z > maxZ) {
          maxZ = z;
        }
      }
    }

    return SurfaceStats(minZ, maxZ);
  }

  double getContourLevel(SurfaceStats stats) {
    return stats.minZ + levelT * (stats.maxZ - stats.minZ);
  }

  Color colorByHeight(double value, double minValue, double maxValue) {
    if ((maxValue - minValue).abs() < 1e-12) {
      return Colors.blue;
    }

    final double t = ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);

    return Color.lerp(Colors.blue, Colors.red, t)!;
  }

  List<Line3D> createAxes() {
    final List<Line3D> lines = [];

    const double axisLength = 7.0;
    const double zLength = 12.0;
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
        Vector3(0, 0, 0),
        Vector3(0, zLength, 0),
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
        Vector3(0.25, zLength - arrow, 0),
        Vector3(0, zLength, 0),
        width: 3,
        color: Colors.green,
      ),
      Line3D(
        Vector3(-0.25, zLength - arrow, 0),
        Vector3(0, zLength, 0),
        width: 3,
        color: Colors.green,
      ),
    ]);

    lines.addAll(createXLabel(axisLength));
    lines.addAll(createYLabel(axisLength));
    lines.addAll(createZLabel(zLength));

    return lines;
  }

  List<Line3D> createXLabel(double axisLength) {
    const color = Colors.red;

    return [
      Line3D(
        Vector3(axisLength + 0.3, -0.35, 0),
        Vector3(axisLength + 0.9, 0.35, 0),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(axisLength + 0.3, 0.35, 0),
        Vector3(axisLength + 0.9, -0.35, 0),
        width: 4,
        color: color,
      ),
    ];
  }

  List<Line3D> createYLabel(double axisLength) {
    const color = Colors.blue;

    return [
      Line3D(
        Vector3(-0.3, 0.35, axisLength + 0.3),
        Vector3(0, 0, axisLength + 0.6),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(0.3, 0.35, axisLength + 0.3),
        Vector3(0, 0, axisLength + 0.6),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(0, 0, axisLength + 0.6),
        Vector3(0, -0.4, axisLength + 0.9),
        width: 4,
        color: color,
      ),
    ];
  }

  List<Line3D> createZLabel(double zLength) {
    const color = Colors.green;

    return [
      Line3D(
        Vector3(-0.35, zLength + 0.7, 0),
        Vector3(0.35, zLength + 0.7, 0),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(0.35, zLength + 0.7, 0),
        Vector3(-0.35, zLength + 0.1, 0),
        width: 4,
        color: color,
      ),
      Line3D(
        Vector3(-0.35, zLength + 0.1, 0),
        Vector3(0.35, zLength + 0.1, 0),
        width: 4,
        color: color,
      ),
    ];
  }

  List<Line3D> createSurface(SurfaceStats stats) {
    final List<Line3D> lines = [];

    const double min = -5;
    const double max = 5;
    const double step = 0.4;

    for (double x = min; x <= max; x += step) {
      for (double y = min; y < max; y += step) {
        final double z1 = f(x, y);
        final double z2 = f(x, y + step);
        final double avg = (z1 + z2) / 2;

        lines.add(
          Line3D(
            Vector3(x, visualZ(z1), y),
            Vector3(x, visualZ(z2), y + step),
            width: 1,
            color: colorByHeight(
              avg,
              stats.minZ,
              stats.maxZ,
            ),
          ),
        );
      }
    }

    for (double y = min; y <= max; y += step) {
      for (double x = min; x < max; x += step) {
        final double z1 = f(x, y);
        final double z2 = f(x + step, y);
        final double avg = (z1 + z2) / 2;

        lines.add(
          Line3D(
            Vector3(x, visualZ(z1), y),
            Vector3(x + step, visualZ(z2), y),
            width: 1,
            color: colorByHeight(
              avg,
              stats.minZ,
              stats.maxZ,
            ),
          ),
        );
      }
    }

    return lines;
  }

  List<Line3D> createLevelPlane(double level,) {
    final List<Line3D> lines = [];

    const double min = -5;
    const double max = 5;
    const double step = 0.5;

    final double planeHeight = visualZ(level);

    const Color planeColor = Color.fromARGB(100, 170, 170, 170);

    for (double x = min; x <= max; x += step) {
      lines.add(
        Line3D(
          Vector3(x, planeHeight, min),
          Vector3(x, planeHeight, max),
          width: 1,
          color: planeColor,
        ),
      );
    }

    for (double y = min; y <= max; y += step) {
      lines.add(
        Line3D(
          Vector3(min, planeHeight, y),
          Vector3(max, planeHeight, y),
          width: 1,
          color: planeColor,
        ),
      );
    }

    return lines;
  }

  List<Line3D> createContourLines(double level,) {
    final List<Line3D> lines = [];

    const double min = -5;
    const double max = 5;
    const double step = 0.25;

    for (double x = min; x < max; x += step) {
      for (double y = min; y < max; y += step) {
        final double z00 = f(x, y);
        final double z10 = f(x + step, y);
        final double z11 = f(x + step, y + step);
        final double z01 = f(x, y + step);

        final List<Offset> intersections = [];

        void addIntersection(
            double x1,
            double y1,
            double z1,
            double x2,
            double y2,
            double z2,
            ) {
          final double minEdge = math.min(z1, z2);
          final double maxEdge = math.max(z1, z2);

          if (level < minEdge || level > maxEdge) {
            return;
          }

          final double difference = z2 - z1;
          if (difference.abs() < 1e-12) {
            return;
          }

          final double t = (level - z1) / difference;

          if (t < 0 || t > 1) {
            return;
          }

          final double px = x1 + t * (x2 - x1);
          final double py = y1 + t * (y2 - y1);

          for (final point in intersections) {
            if ((point.dx - px).abs() < 0.000001 && (point.dy - py).abs() < 0.000001) {
              return;
            }
          }

          intersections.add(
            Offset(
              px,
              py,
            ),
          );
        }

        addIntersection(x, y, z00, x + step, y, z10);
        addIntersection(x + step, y, z10, x + step, y + step, z11);
        addIntersection(x + step, y + step, z11, x, y + step, z01);
        addIntersection(x, y + step, z01, x, y, z00);

        final double height = visualZ(level) + 0.04;

        if (intersections.length == 2) {
          lines.add(
            Line3D(
              Vector3(intersections[0].dx, height, intersections[0].dy),
              Vector3(intersections[1].dx, height, intersections[1].dy),
              width: 4,
              color: Colors.white,
            ),
          );
        }

        if (intersections.length == 4) {
          lines.add(
            Line3D(
              Vector3(intersections[0].dx, height, intersections[0].dy),
              Vector3(intersections[1].dx, height, intersections[1].dy),
              width: 4,
              color: Colors.white,
            ),
          );

          lines.add(
            Line3D(
              Vector3(intersections[2].dx, height, intersections[2].dy),
              Vector3(intersections[3].dx, height, intersections[3].dy),
              width: 4,
              color: Colors.white,
            ),
          );
        }
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
          Vector3(current.x, visualZ(current.z) + 0.05, current.y),
          Vector3(next.x, visualZ(next.z) + 0.05, next.y),
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
          Vector3(point.x, visualZ(point.z) + 0.05, point.y),
          width: 12,
          color: Colors.red,
        ),
      );
    }

    final last = path.last;

    points.add(
      Point3D(
        Vector3(last.x, visualZ(last.z) + 0.05, last.y),
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
          padding:
          const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value.toStringAsFixed(
                  digits,
                ),
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

  Widget functionSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child:
      DropdownButtonFormField<SurfaceFunction>(
        initialValue: selectedFunction,
        decoration: const InputDecoration(
          labelText: 'Функция',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(
            value: SurfaceFunction.rastrigin,
            child: Text('Функция Растригина'),
          ),
          DropdownMenuItem(
            value: SurfaceFunction.rosenbrock,
            child: Text('Функция Розенброка'),
          ),
          DropdownMenuItem(
            value: SurfaceFunction.schafferN2,
            child: Text('Функция Шаффера N2'),
          ),
        ],
        onChanged: (value) {
          if (value == null) {
            return;
          }
          setState(() {
            selectedFunction = value;
            levelT = 0.35;
            clearPath();
          });
        },
      ),
    );
  }
  List<Widget>
  buildFunctionSpecificControls() {
    switch (selectedFunction) {
      case SurfaceFunction.rastrigin:
        return [
          slider(
            title: 'A',
            value: rastriginA,
            min: 1,
            max: 20,
            divisions: 190,
            digits: 1,
            onChanged: (value) {
              setState(() {
                rastriginA = value;
                clearPath();
              });
            },
          ),
        ];

      case SurfaceFunction.rosenbrock:
        return [
          slider(
            title: 'a',
            value: rosenbrockA,
            min: -2,
            max: 2,
            divisions: 40,
            digits: 1,
            onChanged: (value) {
              setState(() {
                rosenbrockA = value;
                clearPath();
              });
            },
          ),
          slider(
            title: 'b',
            value: rosenbrockB,
            min: 1,
            max: 200,
            divisions: 199,
            digits: 0,
            onChanged: (value) {
              setState(() {
                rosenbrockB = value;
                clearPath();
              });
            },
          ),
        ];

      case SurfaceFunction.schafferN2:
        return [];
    }
  }

  @override
  Widget build(BuildContext context,) {
    final SurfaceStats stats = getSurfaceStats();

    final double contourLevel = getContourLevel(stats);

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
                    ...createSurface(stats),
                    ...createLevelPlane(contourLevel),
                    ...createContourLines(contourLevel),
                    ...createAxes(),
                    ...createPathLines(),
                    ...createPathPoints(),
                  ],
                ),
              ),
            ),
          ),
          functionSelector(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            child: Text(
              functionName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            child: Text(
              formulaText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
          Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            child: Text(
              'Уровень: '
                  '${contourLevel.toStringAsFixed(3)}',
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...buildFunctionSpecificControls(),
                  slider(
                    title: 'level',
                    value: levelT,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    digits: 2,
                    onChanged: (value) {
                      setState(() {
                        levelT = value;
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
                    padding: const EdgeInsets.fromLTRB(16, 5, 16, 16),
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
