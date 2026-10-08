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
      theme: ThemeData.dark(),
      home: const PlanetPage(),
    );
  }
}

class PlanetPage extends StatefulWidget {
  const PlanetPage({super.key});

  @override
  State<PlanetPage> createState() => _PlanetPageState();
}

class _PlanetPageState extends State<PlanetPage> with SingleTickerProviderStateMixin {
  cube.Scene? _planetScene;
  cube.Scene? _atmosphereScene;
  cube.Object? _planet;
  cube.Object? _atmosphere;

  Future<List<cube.Mesh>>? _meshesFuture;
  late final AnimationController _controller;
  final Stopwatch _stopwatch = Stopwatch();
  int _previousTime = 0;

  double _planetSpeed = 18;
  double _atmosphereSpeed = -25;
  double _transparency = 30;
  String? _error;

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
    if (_previousTime == 0) {
      _previousTime = now;
      return;
    }

    final double elapsed = (now - _previousTime) / 1000000.0;
    _previousTime = now;
    final double dt = elapsed.clamp(0.0, 0.05).toDouble();

    if (_planet != null && _planetSpeed != 0) {
      _planet!.rotation.y = (_planet!.rotation.y + _planetSpeed * dt) % 360;
      _planet!.updateTransform();
      _planetScene?.update();
    }

    if (_atmosphere != null && _atmosphereSpeed != 0) {
      _atmosphere!.rotation.y = (_atmosphere!.rotation.y + _atmosphereSpeed * dt) % 360;
      _atmosphere!.updateTransform();
      _atmosphereScene?.update();
    }
  }

  void _onPlanetSceneCreated(cube.Scene scene) {
    _planetScene = scene;
    scene.camera.position.z = 16;
    _addModelPart(scene, 'Sphere001', false);
  }

  void _onAtmosphereSceneCreated(cube.Scene scene) {
    _atmosphereScene = scene;
    scene.camera.position.z = 16;
    _addModelPart(scene, 'Sphere002', true);
  }

  Future<void> _addModelPart(cube.Scene scene, String partName, bool isAtmosphere) async {
    try {
      final List<cube.Mesh> meshes = await (_meshesFuture ??= cube.loadObj('assets/earth/earth.obj', true));

      if (!mounted) return;
      if (isAtmosphere && _atmosphereScene != scene) return;
      if (!isAtmosphere && _planetScene != scene) return;

      final cube.Mesh mesh = meshes.firstWhere(
            (item) => item.name == partName,
        orElse: () => throw StateError('Model part not found: $partName'),
      );

      final String texturePath = isAtmosphere
          ? 'assets/earth/4096_clouds.png'
          : 'assets/earth/4096_earth.jpg';

      final texture = await cube.loadImageFromAsset(texturePath);

      if (!mounted) return;
      if (isAtmosphere && _atmosphereScene != scene) return;
      if (!isAtmosphere && _planetScene != scene) return;

      mesh.texture = texture;
      mesh.texturePath = texturePath;
      mesh.textureRect = Rect.fromLTWH(
        0,
        0,
        texture.width.toDouble(),
        texture.height.toDouble(),
      );

      debugPrint('Loaded texture: $texturePath');

      final cube.Object model = cube.Object(
        name: partName,
        mesh: mesh,
        scale: cube.Vector3(10.0, 10.0, 10.0),
        backfaceCulling: true,
      );

      scene.world.add(model);

      if (isAtmosphere) {
        _atmosphere = model;
      } else {
        _planet = model;
      }

      scene.updateTexture();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки модели: $error';
        });
      }
    }
  }

  String _direction(double speed) {
    if (speed == 0) return 'Остановлено';
    if (speed > 0) return 'Против часовой стрелки';
    return 'По часовой стрелке';
  }

  Widget _speedSlider(String title, double speed, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text('${speed.round()} град/с'),
          ],
        ),
        Slider(
          min: -90,
          max: 90,
          divisions: 180,
          value: speed,
          onChanged: onChanged,
        ),
        Text(
          _direction(speed),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
      appBar: AppBar(title: const Text('Планета и атмосфера')),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      cube.Cube(
                        interactive: false,
                        onSceneCreated: _onPlanetSceneCreated,
                      ),
                      Opacity(
                        opacity: 1.0 - _transparency / 100.0,
                        child: cube.Cube(
                          interactive: false,
                          onSceneCreated: _onAtmosphereSceneCreated,
                        ),
                      ),
                      if (_error != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1A2130),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _speedSlider('Скорость планеты', _planetSpeed, (value) {
                    setState(() => _planetSpeed = value);
                  }),
                  const SizedBox(height: 10),
                  _speedSlider('Скорость атмосферы', _atmosphereSpeed, (value) {
                    setState(() => _atmosphereSpeed = value);
                  }),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(child: Text('Прозрачность атмосферы')),
                      Text('${_transparency.round()}%'),
                    ],
                  ),
                  Slider(
                    min: 0,
                    max: 100,
                    divisions: 100,
                    value: _transparency,
                    onChanged: (value) {
                      setState(() => _transparency = value);
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
