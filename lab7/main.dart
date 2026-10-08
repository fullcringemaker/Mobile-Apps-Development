
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cube/flutter_cube.dart' as cube;

void main() {
  runApp(const PlanetApp());
}

class PlanetApp extends StatelessWidget {
  const PlanetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Планета и атмосфера',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PlanetPage(),
    );
  }
}

class PlanetPage extends StatefulWidget {
  const PlanetPage({super.key});

  @override
  State<PlanetPage> createState() => _PlanetPageState();
}

class _PlanetPageState extends State<PlanetPage>
    with SingleTickerProviderStateMixin {
  cube.Scene? _planetScene;
  cube.Scene? _atmosphereScene;
  cube.Object? _planet;
  cube.Object? _atmosphere;

  late final AnimationController _controller;
  final Stopwatch _stopwatch = Stopwatch();
  int _previousMicroseconds = 0;

  // Скорости в градусах за секунду.
  double _planetSpeed = 18;
  double _atmosphereSpeed = -25;

  // Дополнительная прозрачность атмосферы в процентах.
  double _atmosphereTransparency = 30;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(_animate)
      ..repeat();
  }

  void _animate() {
    final int now = _stopwatch.elapsedMicroseconds;

    if (_previousMicroseconds == 0) {
      _previousMicroseconds = now;
      return;
    }

    final double elapsed =
        (now - _previousMicroseconds) / 1000000.0;
    _previousMicroseconds = now;

    // Ограничиваем скачок после длительной паузы.
    final double dt = elapsed > 0.05 ? 0.05 : elapsed;

    // Независимое вращение Земли.
    if (_planet != null && _planetSpeed != 0) {
      _planet!.rotation.y =
          (_planet!.rotation.y + _planetSpeed * dt) % 360;

      _planet!.updateTransform();
      _planetScene?.update();
    }

    // Независимое вращение атмосферы.
    if (_atmosphere != null && _atmosphereSpeed != 0) {
      _atmosphere!.rotation.y =
          (_atmosphere!.rotation.y +
              _atmosphereSpeed * dt) % 360;

      _atmosphere!.updateTransform();
      _atmosphereScene?.update();
    }
  }

  void _onPlanetSceneCreated(cube.Scene scene) {
    _planetScene = scene;
    scene.camera.position.z = 16;

    _addSphere(
      scene: scene,
      texturePath: 'assets/earth/4096_earth.jpg',
      radius: 3.3,
      isAtmosphere: false,
    );
  }

  void _onAtmosphereSceneCreated(cube.Scene scene) {
    _atmosphereScene = scene;
    scene.camera.position.z = 16;

    _addSphere(
      scene: scene,
      texturePath: 'assets/earth/4096_clouds.png',
      radius: 3.4,
      isAtmosphere: true,
    );
  }

  Future<void> _addSphere({
    required cube.Scene scene,
    required String texturePath,
    required double radius,
    required bool isAtmosphere,
  }) async {
    try {
      final cube.Mesh mesh = await _generateSphereMesh(
        radius: radius,
        texturePath: texturePath,
      );

      if (!mounted) return;
      if (isAtmosphere && _atmosphereScene != scene) return;
      if (!isAtmosphere && _planetScene != scene) return;

      final cube.Object sphere = cube.Object(
        name: isAtmosphere ? 'atmosphere' : 'planet',
        mesh: mesh,
        backfaceCulling: true,
      );

      scene.world.add(sphere);

      if (isAtmosphere) {
        _atmosphere = sphere;
      } else {
        _planet = sphere;
      }

      scene.updateTexture();
    } catch (error) {
      debugPrint(
        'Ошибка загрузки текстуры $texturePath: $error',
      );
    }
  }

  // Генерация трёхмерной сферы с текстурой.
  Future<cube.Mesh> _generateSphereMesh({
    required double radius,
    required String texturePath,
  }) async {
    const int latSegments = 32;
    const int lonSegments = 64;

    final List<cube.Vector3> vertices = [];
    final List<Offset> texcoords = [];
    final List<cube.Polygon> triangles = [];

    // Создаём вершины сферы.
    for (int y = 0; y <= latSegments; y++) {
      final double v = y / latSegments;
      final double sv = math.sin(v * math.pi);
      final double cv = math.cos(v * math.pi);

      for (int x = 0; x <= lonSegments; x++) {
        final double u = x / lonSegments;

        vertices.add(
          cube.Vector3(
            radius * math.cos(u * 2 * math.pi) * sv,
            radius * cv,
            radius * math.sin(u * 2 * math.pi) * sv,
          ),
        );

        texcoords.add(Offset(1.0 - u, 1.0 - v));
      }
    }

    // Соединяем вершины треугольниками.
    for (int y = 0; y < latSegments; y++) {
      final int row1 = y * (lonSegments + 1);
      final int row2 = (y + 1) * (lonSegments + 1);

      for (int x = 0; x < lonSegments; x++) {
        triangles.add(
          cube.Polygon(
            row1 + x,
            row1 + x + 1,
            row2 + x,
          ),
        );

        triangles.add(
          cube.Polygon(
            row1 + x + 1,
            row2 + x + 1,
            row2 + x,
          ),
        );
      }
    }

    // Загружаем картинку для поверхности сферы.
    final ui.Image image =
    await cube.loadImageFromAsset(texturePath);

    return cube.Mesh(
      vertices: vertices,
      texcoords: texcoords,
      indices: triangles,
      texture: image,
      texturePath: texturePath,
    );
  }

  // Ползунок скорости для планеты или атмосферы.
  Widget _buildSpeedSlider({
    required String title,
    required double speed,
    required ValueChanged<double> onChanged,
  }) {
    final String direction = speed == 0
        ? 'Остановлено'
        : speed > 0
        ? 'Против часовой (вид со стороны северного полюса)'
        : 'По часовой (вид со стороны северного полюса)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15),
              ),
            ),
            Text('${speed.toStringAsFixed(0)} °/с'),
          ],
        ),
        Slider(
          min: -90,
          max: 90,
          divisions: 180,
          value: speed,
          label: '${speed.toStringAsFixed(0)} °/с',
          onChanged: onChanged,
        ),
        Text(
          direction,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Планета и атмосфера'),
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Верхняя область: 3D-модель.
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Нижний слой: планета.
                      CubeLayer(
                        onSceneCreated:
                        _onPlanetSceneCreated,
                      ),

                      // Верхний слой: атмосфера.
                      Opacity(
                        opacity:
                        1 - _atmosphereTransparency / 100,
                        child: CubeLayer(
                          onSceneCreated:
                          _onAtmosphereSceneCreated,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Нижняя область: настройки.
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF161C29),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  _buildSpeedSlider(
                    title: 'Вращение планеты',
                    speed: _planetSpeed,
                    onChanged: (value) {
                      setState(() {
                        _planetSpeed = value;
                      });
                    },
                  ),

                  const SizedBox(height: 12),

                  _buildSpeedSlider(
                    title: 'Вращение атмосферы',
                    speed: _atmosphereSpeed,
                    onChanged: (value) {
                      setState(() {
                        _atmosphereSpeed = value;
                      });
                    },
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Прозрачность атмосферы',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                      Text(
                        '${_atmosphereTransparency.round()}%',
                      ),
                    ],
                  ),

                  Slider(
                    min: 0,
                    max: 100,
                    divisions: 100,
                    value: _atmosphereTransparency,
                    label:
                    '${_atmosphereTransparency.round()}%',
                    onChanged: (value) {
                      setState(() {
                        _atmosphereTransparency = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Независимая 3D-сцена для одного слоя.
class CubeLayer extends StatelessWidget {
  const CubeLayer({
    super.key,
    required this.onSceneCreated,
  });

  final cube.SceneCreatedCallback onSceneCreated;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: cube.Cube(
        interactive: false,
        onSceneCreated: onSceneCreated,
      ),
    );
  }
}
