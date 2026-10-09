import 'dart:math' as math;

import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  double indexAngle = 0;
  double middleAngle = 0;
  double ringAngle = 0;
  double pinkyAngle = 0;
  double handX = 0;
  double handY = 0;
  double handZ = 0;

  late final Future<List<Mesh3D>> handMeshes = _loadHand();
  late final Mesh3D cylinder = _makeCylinder();

  final DiTreDiController _controller = DiTreDiController(
    rotationX: 0,
    rotationY: 0,
    light: vector.Vector3(-0.5, -0.5, 0.5),
  );

  double get grip =>
      [indexAngle, middleAngle, ringAngle, pinkyAngle].reduce(math.min) / 12;

  TransformModifier3D _moveWithHand(Model3D model, vector.Matrix4 local) {
    return TransformModifier3D(
      model,
      vector.Matrix4.identity()
        ..translateByDouble(handX, handY, handZ, 1)
        ..multiply(local),
    );
  }

  vector.Matrix4 _fingerMatrix({
    required double x,
    required double y,
    required double z,
    required double pivotX,
    required double pivotY,
    required double pivotZ,
    required double angle,
  }) {
    return vector.Matrix4.identity()
      ..rotateX(-math.pi / 2)
      ..translateByDouble(x, y, z, 1)
      ..translateByDouble(-pivotX, -pivotY, -pivotZ, 1)
      ..rotateX(-(angle * math.pi / 18))
      ..translateByDouble(pivotX, pivotY, pivotZ, 1);
  }

  List<Model3D> _figures(List<Mesh3D> meshes) {
    final radius = 1.1 - 0.3 * grip;
    return [
      _moveWithHand(
        cylinder,
        vector.Matrix4.identity()
          ..translateByDouble(-0.5, 5.1, -1.5, 1)
          ..scaleByDouble(4.9, radius, radius, 1),
      ),
      _moveWithHand(
        meshes[0],
        vector.Matrix4.identity()..rotateX(-math.pi / 2),
      ),
      _moveWithHand(
        meshes[1],
        _fingerMatrix(
          x: 3.05,
          y: 1.15,
          z: 8.75,
          pivotX: 0.2,
          pivotY: 0.25,
          pivotZ: 2.2,
          angle: indexAngle,
        ),
      ),
      _moveWithHand(
        meshes[2],
        _fingerMatrix(
          x: 0.7,
          y: 0,
          z: 9.75,
          pivotX: 0,
          pivotY: 0.5,
          pivotZ: 2.25,
          angle: middleAngle,
        ),
      ),
      _moveWithHand(
        meshes[3],
        _fingerMatrix(
          x: -2.0,
          y: -0.56,
          z: 9.1,
          pivotX: 0,
          pivotY: 0.25,
          pivotZ: 2.2,
          angle: ringAngle,
        ),
      ),
      _moveWithHand(
        meshes[4],
        _fingerMatrix(
          x: -4.65,
          y: -1.0,
          z: 7.15,
          pivotX: 0,
          pivotY: 0,
          pivotZ: 1.25,
          angle: pinkyAngle,
        ),
      ),
    ];
  }

  Widget _slider(
    String name,
    double value,
    ValueChanged<double> onChanged, {
    double min = 0,
    double max = 12,
    int? divisions,
  }) {
    return Row(
      children: [
        SizedBox(width: 115, child: Text(name)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(1),
            onChanged: (newValue) => setState(() => onChanged(newValue)),
          ),
        ),
        SizedBox(width: 45, child: Text(value.toStringAsFixed(1))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Захват цилиндра',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Захват цилиндра')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: FutureBuilder<List<Mesh3D>>(
                  future: handMeshes,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Ошибка загрузки модели: ${snapshot.error}',
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Поверните модель пальцем; измените масштаб жестом',
                ),
              ),
              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    const Text('Сгибание пальцев'),
                    _slider(
                      'Указательный',
                      indexAngle,
                      (value) => indexAngle = value,
                      divisions: 13,
                    ),
                    _slider(
                      'Средний',
                      middleAngle,
                      (value) => middleAngle = value,
                      divisions: 13,
                    ),
                    _slider(
                      'Безымянный',
                      ringAngle,
                      (value) => ringAngle = value,
                      divisions: 13,
                    ),
                    _slider(
                      'Мизинец',
                      pinkyAngle,
                      (value) => pinkyAngle = value,
                      divisions: 13,
                    ),
                    Text('Сжатие цилиндра: ${(grip * 100).round()}%'),
                    const Divider(),
                    const Text('Перемещение руки с цилиндром'),
                    _slider(
                      'X',
                      handX,
                      (value) => handX = value,
                      min: -10,
                      max: 10,
                      divisions: 40,
                    ),
                    _slider(
                      'Y',
                      handY,
                      (value) => handY = value,
                      min: -10,
                      max: 10,
                      divisions: 40,
                    ),
                    _slider(
                      'Z',
                      handZ,
                      (value) => handZ = value,
                      min: -10,
                      max: 10,
                      divisions: 40,
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

Future<List<Mesh3D>> _loadHand() async {
  final parser = ObjParser();
  return [
    Mesh3D(await parser.loadFromResources('assets/hand/hand.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/index.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/middle.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/ring.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/pinky.obj')),
  ];
}

Mesh3D _makeCylinder() {
  const segments = 32;
  const lengthSegments = 24;
  final faces = <Face3D>[];
  final left = vector.Vector3(-1, 0, 0);
  final right = vector.Vector3(1, 0, 0);

  for (var i = 0; i < segments; i++) {
    final a = 2 * math.pi * i / segments;
    final b = 2 * math.pi * (i + 1) / segments;
    final cosA = math.cos(a);
    final sinA = math.sin(a);
    final cosB = math.cos(b);
    final sinB = math.sin(b);
    for (var j = 0; j < lengthSegments; j++) {
      final x0 = -1 + 2 * j / lengthSegments;
      final x1 = -1 + 2 * (j + 1) / lengthSegments;
      final l0 = vector.Vector3(x0, cosA, sinA);
      final l1 = vector.Vector3(x0, cosB, sinB);
      final r0 = vector.Vector3(x1, cosA, sinA);
      final r1 = vector.Vector3(x1, cosB, sinB);
      faces.add(
        Face3D.fromVertices(l0, r1, r0, color: const Color(0xFFFF9800)),
      );
      faces.add(
        Face3D.fromVertices(l0, l1, r1, color: const Color(0xFFFF9800)),
      );
    }
    faces.add(
      Face3D.fromVertices(
        left,
        vector.Vector3(-1, cosB, sinB),
        vector.Vector3(-1, cosA, sinA),
        color: const Color(0xFFE65100),
      ),
    );
    faces.add(
      Face3D.fromVertices(
        right,
        vector.Vector3(1, cosA, sinA),
        vector.Vector3(1, cosB, sinB),
        color: const Color(0xFFE65100),
      ),
    );
  }
  return Mesh3D(faces);
}
