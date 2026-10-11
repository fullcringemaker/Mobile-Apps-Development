import 'dart:math' as math;

import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  static const double _ballRadius = 0.42;
  static const double _impulseSpeed = 6.5;
  static const double _wallFaceX = 14.0;

  double bend = 0;
  double handX = 0;
  double handY = 0;
  double handZ = 0;
  double racketAngle = 0;
  bool gripped = false;
  bool ballOut = false;

  vector.Vector3 ballPosition = vector.Vector3(2.0, 11.8, -1.5);
  vector.Vector3 ballVelocity = vector.Vector3.zero(); // Initial w = 0.

  late final Future<List<Mesh3D>> models = _loadModels();
  late final Mesh3D ballMesh = _makeSphere(_ballRadius);
  late final Mesh3D wallMesh = _makeBox(
    vector.Vector3(14, 2, -7),
    vector.Vector3(14.8, 20, 7),
    const Color(0xFF78909C),
  );
  late final Ticker _ticker;
  Duration? _previousTick;

  final DiTreDiController _controller = DiTreDiController(
    rotationX: -10,
    rotationY: -35,
    light: vector.Vector3(-0.5, -0.5, 0.5),
  );

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  vector.Matrix4 _handPose() => vector.Matrix4.identity()
    ..translateByDouble(handX, handY, handZ, 1)
    ..rotateY(racketAngle * math.pi / 180);

  vector.Matrix4 _racketMatrix() => _handPose()
    ..translateByDouble(0, 5.1, -1.5, 1)
    ..rotateZ(math.pi / 2)
    ..scaleByDouble(1.4, 1.4, 1.4, 1);

  vector.Vector3 _racketCenter() =>
      _racketMatrix().transform3(vector.Vector3(4.8, 0, 0));

  vector.Vector3 _racketNormal() {
    final radians = racketAngle * math.pi / 180;
    return vector.Vector3(math.cos(radians), 0, -math.sin(radians));
  }

  vector.Matrix4 _fingerMatrix({
    required double x,
    required double y,
    required double z,
    required double pivotX,
    required double pivotY,
    required double pivotZ,
  }) {
    return vector.Matrix4.identity()
      ..rotateX(-math.pi / 2)
      ..translateByDouble(x, y, z, 1)
      ..translateByDouble(-pivotX, -pivotY, -pivotZ, 1)
      ..rotateX(-(bend * math.pi / 18))
      ..translateByDouble(pivotX, pivotY, pivotZ, 1);
  }

  TransformModifier3D _handPart(Model3D mesh, vector.Matrix4 local) {
    // Rotate the right-hand grip around the vertical handle so the fingers
    // point toward the wall while the index stays above the pinky.
    return TransformModifier3D(
      mesh,
      _handPose()
        ..translateByDouble(-2.0, 5.3, -1.7, 1)
        ..rotateY(math.pi)
        ..rotateZ(math.pi / 2)
        ..scaleByDouble(0.35, 0.35, 0.35, 1)
        ..multiply(local),
    );
  }

  List<Model3D> _figures(List<Mesh3D> meshes) => [
    wallMesh,
    TransformModifier3D(
      ballMesh,
      vector.Matrix4.identity()..translateByVector3(ballPosition),
    ),
    TransformModifier3D(meshes[5], _racketMatrix()),
    _handPart(meshes[0], vector.Matrix4.identity()..rotateX(-math.pi / 2)),
    _handPart(
      meshes[1],
      _fingerMatrix(
        x: 3.05,
        y: 1.15,
        z: 8.75,
        pivotX: 0.2,
        pivotY: 0.25,
        pivotZ: 2.2,
      ),
    ),
    _handPart(
      meshes[2],
      _fingerMatrix(
        x: 0.7,
        y: 0,
        z: 9.75,
        pivotX: 0,
        pivotY: 0.5,
        pivotZ: 2.25,
      ),
    ),
    _handPart(
      meshes[3],
      _fingerMatrix(
        x: -2,
        y: -0.56,
        z: 9.1,
        pivotX: 0,
        pivotY: 0.25,
        pivotZ: 2.2,
      ),
    ),
    _handPart(
      meshes[4],
      _fingerMatrix(
        x: -4.65,
        y: -1,
        z: 7.15,
        pivotX: 0,
        pivotY: 0,
        pivotZ: 1.25,
      ),
    ),
  ];

  void _grabRacket() {
    if (gripped || bend < 12) return;
    gripped = true;
    ballOut = false;
    final normal = _racketNormal();
    ballPosition = _racketCenter() + normal.scaled(2.0);
    ballVelocity = normal.scaled(_impulseSpeed);
    _previousTick = null;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final previous = _previousTick;
    _previousTick = elapsed;
    if (previous == null || !gripped || ballOut) return;
    var remaining = ((elapsed - previous).inMicroseconds / 1000000).clamp(
      0.0,
      0.05,
    );
    while (remaining > 0 && !ballOut) {
      final step = math.min(remaining, 1 / 120);
      _advanceBall(step);
      remaining -= step;
    }
    if (mounted) setState(() {});
  }

  void _advanceBall(double dt) {
    final oldPosition = ballPosition.clone();
    ballPosition.add(ballVelocity.scaled(dt));

    // The wall is fixed. Only the component perpendicular to it reverses.
    final wallContact = _wallFaceX - _ballRadius;
    if (ballVelocity.x > 0 &&
        oldPosition.x < wallContact &&
        ballPosition.x >= wallContact &&
        ballPosition.y >= 2 &&
        ballPosition.y <= 20 &&
        ballPosition.z >= -7 &&
        ballPosition.z <= 7) {
      ballPosition.x = 2 * wallContact - ballPosition.x;
      ballVelocity.x = -ballVelocity.x;
    }

    // A finite elliptical hit area approximates the racket's string bed.
    final center = _racketCenter();
    final normal = _racketNormal();
    final oldDistance = (oldPosition - center).dot(normal);
    final distance = (ballPosition - center).dot(normal);
    final tangent = vector.Vector3(-normal.z, 0, normal.x);
    final relative = ballPosition - center;
    final vertical = relative.y / 3.3;
    final sideways = relative.dot(tangent) / 2.55;
    if (ballVelocity.dot(normal) < 0 &&
        oldDistance > _ballRadius &&
        distance <= _ballRadius &&
        vertical * vertical + sideways * sideways <= 1) {
      ballPosition.add(normal.scaled(2 * (_ballRadius - distance)));
      ballVelocity.sub(normal.scaled(2 * ballVelocity.dot(normal)));
    }

    if (ballPosition.x < -8 ||
        ballPosition.x > 21 ||
        ballPosition.y < -11 ||
        ballPosition.y > 24 ||
        ballPosition.z < -11 ||
        ballPosition.z > 11) {
      ballOut = true;
      _ticker.stop();
    }
  }

  void _reset() {
    _ticker.stop();
    _previousTick = null;
    setState(() {
      bend = 0;
      handX = 0;
      handY = 0;
      handZ = 0;
      racketAngle = 0;
      gripped = false;
      ballOut = false;
      ballPosition = vector.Vector3(2.0, 11.8, -1.5);
      ballVelocity = vector.Vector3.zero();
    });
  }

  Widget _slider(
    String name,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double>? onChanged,
  ) => Row(
    children: [
      SizedBox(width: 85, child: Text(name)),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 45, child: Text(value.toStringAsFixed(1))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ракетка и мяч',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Ракетка и мяч')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: FutureBuilder<List<Mesh3D>>(
                  future: models,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Ошибка загрузки моделей: ${snapshot.error}',
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return DiTreDiDraggable(
                      controller: _controller,
                      child: DiTreDi(
                        figures: _figures(snapshot.data!),
                        controller: _controller,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ballOut
                            ? 'Мяч улетел за пределы сцены'
                            : gripped
                            ? 'Мяч движется: отражение от стены и ракетки'
                            : 'Сожмите пальцы до конца, чтобы взять ракетку',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.replay),
                      label: const Text('Сброс'),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _slider(
                      'Хват',
                      bend,
                      0,
                      12,
                      12,
                      gripped
                          ? null
                          : (value) {
                              setState(() {
                                bend = value;
                                _grabRacket();
                              });
                            },
                    ),
                    if (gripped) ...[
                      const Divider(),
                      _slider(
                        'X',
                        handX,
                        -8,
                        8,
                        32,
                        (value) => setState(() => handX = value),
                      ),
                      _slider(
                        'Y',
                        handY,
                        -8,
                        8,
                        32,
                        (value) => setState(() => handY = value),
                      ),
                      _slider(
                        'Z',
                        handZ,
                        -8,
                        8,
                        32,
                        (value) => setState(() => handZ = value),
                      ),
                      _slider(
                        'Угол °',
                        racketAngle,
                        -60,
                        60,
                        48,
                        (value) => setState(() => racketAngle = value),
                      ),
                    ],
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

Future<List<Mesh3D>> _loadModels() async {
  final parser = ObjParser();
  return [
    Mesh3D(await parser.loadFromResources('assets/hand/hand.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/index.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/middle.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/ring.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/pinky.obj')),
    Mesh3D(await parser.loadFromResources('assets/racket/racket.obj')),
  ];
}

Mesh3D _makeSphere(double radius) {
  const rings = 12;
  const segments = 18;
  final faces = <Face3D>[];
  vector.Vector3 point(int ring, int segment) {
    final theta = math.pi * ring / rings;
    final phi = 2 * math.pi * segment / segments;
    return vector.Vector3(
      radius * math.sin(theta) * math.cos(phi),
      radius * math.cos(theta),
      radius * math.sin(theta) * math.sin(phi),
    );
  }

  for (var ring = 0; ring < rings; ring++) {
    for (var segment = 0; segment < segments; segment++) {
      final a = point(ring, segment);
      final b = point(ring + 1, segment);
      final c = point(ring + 1, segment + 1);
      final d = point(ring, segment + 1);
      if (ring > 0) {
        faces.add(Face3D.fromVertices(a, d, c, color: const Color(0xFFFFEB3B)));
      }
      if (ring < rings - 1) {
        faces.add(Face3D.fromVertices(a, c, b, color: const Color(0xFFFFEB3B)));
      }
    }
  }
  return Mesh3D(faces);
}

Mesh3D _makeBox(vector.Vector3 min, vector.Vector3 max, Color color) {
  vector.Vector3 p(double x, double y, double z) => vector.Vector3(x, y, z);
  final faces = <Face3D>[];
  void side(
    vector.Vector3 a,
    vector.Vector3 b,
    vector.Vector3 c,
    vector.Vector3 d,
  ) {
    faces.add(Face3D.fromVertices(a, b, c, color: color));
    faces.add(Face3D.fromVertices(a, c, d, color: color));
  }

  side(
    p(min.x, min.y, min.z),
    p(min.x, min.y, max.z),
    p(min.x, max.y, max.z),
    p(min.x, max.y, min.z),
  );
  side(
    p(max.x, min.y, max.z),
    p(max.x, min.y, min.z),
    p(max.x, max.y, min.z),
    p(max.x, max.y, max.z),
  );
  side(
    p(min.x, min.y, min.z),
    p(max.x, min.y, min.z),
    p(max.x, min.y, max.z),
    p(min.x, min.y, max.z),
  );
  side(
    p(min.x, max.y, max.z),
    p(max.x, max.y, max.z),
    p(max.x, max.y, min.z),
    p(min.x, max.y, min.z),
  );
  side(
    p(min.x, max.y, min.z),
    p(max.x, max.y, min.z),
    p(max.x, min.y, min.z),
    p(min.x, min.y, min.z),
  );
  side(
    p(min.x, min.y, max.z),
    p(max.x, min.y, max.z),
    p(max.x, max.y, max.z),
    p(min.x, max.y, max.z),
  );
  return Mesh3D(faces);
}
