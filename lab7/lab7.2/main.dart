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

  double _positionX = 0;
  double _positionY = 0;
  double _positionZ = 0;

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

  void _updatePosition() {
    if (_planet != null) {
      _planet!.position.x = _positionX;
      _planet!.position.y = _positionY;
      _planet!.position.z = _positionZ;
      _planet!.updateTransform();
      _planetScene?.update();
    }

    if (_atmosphere != null) {
      _atmosphere!.position.x = _positionX;
      _atmosphere!.position.y = _positionY;
      _atmosphere!.position.z = _positionZ;
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

      final cube.Object model = cube.Object(
        name: partName,
        mesh: mesh,
        position: cube.Vector3(_positionX, _positionY, _positionZ),
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
            Text('${speed.round()} grad/s'),
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

  Widget _positionSlider(String axis, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('Положение $axis')),
            Text(value.toStringAsFixed(1)),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: ((max - min) * 10).round(),
          value: value,
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
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
              flex: 5,
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
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A2130),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Вращение',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _speedSlider('Скорость планеты', _planetSpeed, (value) {
                        setState(() => _planetSpeed = value);
                      }),
                      const SizedBox(height: 10),
                      _speedSlider('Скорость атмосферы', _atmosphereSpeed,
                              (value) {
                            setState(() => _atmosphereSpeed = value);
                          }),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Expanded(
                              child: Text('Прозрачность атмосферы')),
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
                      const Divider(height: 30),
                      const Text(
                        'Перемещение планеты',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _positionSlider('X', _positionX, -3, 3, (value) {
                        setState(() => _positionX = value);
                        _updatePosition();
                      }),
                      _positionSlider('Y', _positionY, -3, 3, (value) {
                        setState(() => _positionY = value);
                        _updatePosition();
                      }),
                      _positionSlider('Z', _positionZ, -4, 4, (value) {
                        setState(() => _positionZ = value);
                        _updatePosition();
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
