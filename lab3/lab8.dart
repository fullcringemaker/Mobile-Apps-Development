import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:vector_math/vector_math_64.dart' as vector;


class PlayerPose {
  const PlayerPose({
    required this.id,
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.yaw = 0,
    this.pitch = 0,
    this.bend = 0,
    this.gripped = false,
  });
  final int id;
  final double x, y, z, yaw, pitch, bend;
  final bool gripped;

  factory PlayerPose.fromJson(Map<String, dynamic> data) => PlayerPose(
    id: data['id'] as int,
    x: (data['x'] as num).toDouble(),
    y: (data['y'] as num).toDouble(),
    z: (data['z'] as num).toDouble(),
    yaw: (data['yaw'] as num).toDouble(),
    pitch: (data['pitch'] as num).toDouble(),
    bend: (data['bend'] as num).toDouble(),
    gripped: data['gripped'] as bool,
  );

  static PlayerPose mix(PlayerPose a, PlayerPose b, double t) {
    double lerp(double x, double y) => x + (y - x) * t;
    return PlayerPose(
      id: b.id,
      x: lerp(a.x, b.x),
      y: lerp(a.y, b.y),
      z: lerp(a.z, b.z),
      yaw: lerp(a.yaw, b.yaw),
      pitch: lerp(a.pitch, b.pitch),
      bend: lerp(a.bend, b.bend),
      gripped: b.gripped,
    );
  }
}

class TennisPage extends StatefulWidget {
  const TennisPage({super.key});

  @override
  State<TennisPage> createState() => _TennisPageState();
}

class _TennisPageState extends State<TennisPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _ballRadius = 0.42;
  static const _playerColors = [Color(0xFF1565C0), Color(0xFFEF6C00)];
  static const _serverUrl = 'ws://net11.yss.su:9742';
  final _pressed = <int, String>{};
  double _cameraScale = 1.8;
  final _controller = DiTreDiController(
    rotationX: 0,
    rotationY: -90,
    userScale: 1.8,
    light: vector.Vector3(-0.5, -0.5, 0.5),
  );
  final _bounds = vector.Aabb3.minMax(
    vector.Vector3(-8, -10, -22),
    vector.Vector3(16, 32, 22),
  );
  late final Future<List<Mesh3D>> _models = _loadModels();
  late final Mesh3D _ballMesh = _makeSphere(_ballRadius);
  late final Mesh3D _wallMesh = _makeBox(
    vector.Vector3(14, -4, -16),
    vector.Vector3(15.6, 26, 16),
    const Color(0xFF78909C),
  );
  late final AnimationController _blend;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat, _joinDeadline;
  int _generation = 0, _slot = 1;
  bool _showForm = true, _connecting = false, _connected = false;
  bool _paused = false;
  String _notice = '', _phase = 'waiting';
  List<PlayerPose> _from = const [
    PlayerPose(id: 1, z: 5, yaw: 20),
    PlayerPose(id: 2, z: -5, yaw: -20),
  ];
  List<PlayerPose> _to = const [
    PlayerPose(id: 1, z: 5, yaw: 20),
    PlayerPose(id: 2, z: -5, yaw: -20),
  ];
  vector.Vector3 _ballFrom = vector.Vector3(2, 11.82, -1.1);
  vector.Vector3 _ballTo = vector.Vector3(2, 11.82, -1.1);

  List<PlayerPose> get _visiblePlayers => [
    for (var i = 0; i < 2; i++) PlayerPose.mix(_from[i], _to[i], _blend.value),
  ];
  vector.Vector3 get _visibleBall =>
      _ballFrom + (_ballTo - _ballFrom).scaled(_blend.value);
  PlayerPose get _me => _to[_slot - 1];
  bool get _canMove => _connected && _me.gripped && !_paused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _blend = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 34),
      value: 1,
    )..addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (_paused) {
      _pressed.clear();
      _sendInput();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _joinDeadline?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _blend.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!mounted || _connecting) return;
    _joinDeadline?.cancel();
    _heartbeat?.cancel();
    _pressed.clear();
    _connecting = true;
    final generation = ++_generation;
    await _subscription?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    if (!mounted || generation != _generation) return;
    setState(() {
      _connecting = true;
      _connected = false;
      _notice = '';
    });
    try {
      final channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      _channel = channel;
      _subscription = channel.stream.listen(
            (event) => _receive(event, generation),
        onError: (Object error) => _lost(generation),
        onDone: () => _lost(generation),
        cancelOnError: true,
      );
      await channel.ready.timeout(const Duration(seconds: 8));
      if (generation != _generation || !mounted) return;
      channel.sink.add(jsonEncode({'type': 'join', 'player': _slot}));
      _joinDeadline = Timer(const Duration(seconds: 8), () {
        _lost(generation);
      });
    } catch (_) {
      _lost(generation);
    }
  }

  void _receive(dynamic event, int generation) {
    if (generation != _generation || !mounted || event is! String) return;
    try {
      final data = jsonDecode(event) as Map<String, dynamic>;
      if (data['type'] == 'error') {
        _lost(generation, 'Место занято');
        return;
      }
      if (data['type'] == 'welcome') {
        _joinDeadline?.cancel();
        _slot = data['player'] as int;
        setState(() {
          _connected = true;
          _connecting = false;
          _showForm = false;
          _notice = '';
        });
        _heartbeat = Timer.periodic(
          const Duration(milliseconds: 50),
              (_) => _sendInput(),
        );
      } else if (data['type'] == 'state') {
        final players = (data['players'] as List)
            .map((p) => PlayerPose.fromJson(p as Map<String, dynamic>))
            .toList();
        if (players.length != 2 || players[0].id != 1 || players[1].id != 2) {
          throw const FormatException();
        }
        final pos = data['ball'] as List;
        final ball = vector.Vector3(
          (pos[0] as num).toDouble(),
          (pos[1] as num).toDouble(),
          (pos[2] as num).toDouble(),
        );
        final changedPhase = data['phase'] != _phase;
        _from = changedPhase ? players : _visiblePlayers;
        _ballFrom = changedPhase ? ball.clone() : _visibleBall;
        _to = players;
        _ballTo = ball;
        _phase = data['phase'] as String;
        _blend.forward(from: changedPhase ? 1 : 0);
        setState(() {});
      }
    } catch (_) {
      _lost(generation);
    }
  }

  void _lost(int generation, [String message = 'Нет связи с сервером']) {
    if (generation != _generation || !mounted) return;
    _generation++;
    _heartbeat?.cancel();
    _joinDeadline?.cancel();
    _blend.stop();
    _pressed.clear();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    setState(() {
      _connected = false;
      _connecting = false;
      _notice = message;
    });
  }

  void _send(Map<String, dynamic> data) {
    if (!_connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {
      _lost(_generation);
    }
  }

  void _sendInput() => _send({
    'type': 'input',
    'actions': _canMove ? _pressed.values.toSet().toList() : <String>[],
  });

  void _settings() {
    _send({'type': 'input', 'actions': <String>[]});
    _generation++;
    _heartbeat?.cancel();
    _joinDeadline?.cancel();
    _pressed.clear();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    setState(() {
      _showForm = true;
      _connected = false;
      _connecting = false;
      _notice = '';
    });
  }

  vector.Matrix4 _handPose(PlayerPose p) => vector.Matrix4.identity()
    ..translateByDouble(p.x, p.y, p.z, 1)
    ..rotateY(p.yaw * math.pi / 180)
    ..rotateZ(p.pitch * math.pi / 180);

  vector.Matrix4 _racketMatrix(PlayerPose p) => _handPose(p)
    ..translateByDouble(-0.5, 5.1, -1.1, 1)
    ..rotateZ(math.pi / 2)
    ..scaleByDouble(1.4, 1.4, 1.4, 1);

  vector.Matrix4 _fingerMatrix(
      PlayerPose p,
      double x,
      double y,
      double z,
      double pivotX,
      double pivotY,
      double pivotZ,
      ) => vector.Matrix4.identity()
    ..rotateX(-math.pi / 2)
    ..translateByDouble(x, y, z, 1)
    ..translateByDouble(-pivotX, -pivotY, -pivotZ, 1)
    ..rotateX(-(p.bend * math.pi / 18))
    ..translateByDouble(pivotX, pivotY, pivotZ, 1);

  TransformModifier3D _handPart(
      PlayerPose p,
      Model3D mesh,
      vector.Matrix4 local,
      ) => TransformModifier3D(
    mesh,
    _handPose(p)
      ..translateByDouble(-2, 5.3, -1.7, 1)
      ..rotateY(math.pi)
      ..rotateZ(math.pi / 2)
      ..scaleByDouble(0.35, 0.35, 0.35, 1)
      ..multiply(local),
  );

  List<Model3D> _figures(List<Mesh3D> meshes) {
    return [
      _wallMesh,
      TransformModifier3D(
        _ballMesh,
        vector.Matrix4.identity()..translateByVector3(_visibleBall),
      ),
      for (final p in _visiblePlayers) ...[
        TransformModifier3D(meshes[p.id == 1 ? 5 : 6], _racketMatrix(p)),
        _handPart(
          p,
          meshes[0],
          vector.Matrix4.identity()..rotateX(-math.pi / 2),
        ),
        _handPart(
          p,
          meshes[1],
          _fingerMatrix(p, 3.05, 1.15, 8.75, 0.2, 0.25, 2.2),
        ),
        _handPart(p, meshes[2], _fingerMatrix(p, 0.7, 0, 9.75, 0, 0.5, 2.25)),
        _handPart(p, meshes[3], _fingerMatrix(p, -2, -0.56, 9.1, 0, 0.25, 2.2)),
        _handPart(p, meshes[4], _fingerMatrix(p, -4.65, -1, 7.15, 0, 0, 1.25)),
      ],
    ];
  }

  Widget _connectForm() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Игрок 1')),
                ButtonSegment(value: 2, label: Text('Игрок 2')),
              ],
              selected: {_slot},
              onSelectionChanged: _connecting
                  ? null
                  : (v) => setState(() => _slot = v.first),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _connecting ? null : () => _connect(),
              child: Text(_connecting ? 'Подключение' : 'Подключиться'),
            ),
            if (_notice.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_notice, style: const TextStyle(color: Colors.deepOrange)),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _holdButton(String label, String action, {IconData? icon}) {
    final enabled = _canMove;
    final held = _pressed.containsValue(action);
    return Tooltip(
      message: 'Удерживайте: $label',
      child: Listener(
        key: ValueKey('control-$action'),
        onPointerDown: !enabled
            ? null
            : (event) {
          setState(() => _pressed[event.pointer] = action);
          _sendInput();
        },
        onPointerUp: (event) {
          setState(() => _pressed.remove(event.pointer));
          _sendInput();
        },
        onPointerCancel: (event) {
          setState(() => _pressed.remove(event.pointer));
          _sendInput();
        },
        child: Semantics(
          label: label,
          button: true,
          enabled: enabled,
          child: Container(
            constraints: const BoxConstraints(minHeight: 50, minWidth: 54),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !enabled
                  ? Colors.grey.shade200
                  : held
                  ? _playerColors[_slot - 1]
                  : _playerColors[_slot - 1].withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled
                    ? _playerColors[_slot - 1]
                    : Colors.grey.shade300,
              ),
            ),
            child: icon != null
                ? Icon(
              icon,
              color: !enabled
                  ? Colors.grey
                  : held
                  ? Colors.white
                  : _playerColors[_slot - 1],
            )
                : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: !enabled
                      ? Colors.grey
                      : held
                      ? Colors.white
                      : _playerColors[_slot - 1],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pair(String left, String a, String right, String b) => Row(
    children: [
      Expanded(child: _holdButton(left, a)),
      const SizedBox(width: 8),
      Expanded(child: _holdButton(right, b)),
    ],
  );

  Widget _controls() => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_connected) ...[
          Text(_notice, style: const TextStyle(color: Colors.deepOrange)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _connecting ? null : () => _connect(),
            child: Text(_connecting ? 'Подключение' : 'Подключиться снова'),
          ),
        ] else if (!_me.gripped)
          FilledButton(
            onPressed: () => _send({'type': 'grab'}),
            child: Text(_me.bend > 0 ? 'Сжимаем пальцы' : 'Взять ракетку'),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Spacer(),
            Expanded(
              child: _holdButton('Вверх', 'y_plus', icon: Icons.arrow_upward),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _holdButton('Влево', 'z_plus', icon: Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _holdButton('Вниз', 'y_minus', icon: Icons.arrow_downward),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _holdButton(
                'Вправо',
                'z_minus',
                icon: Icons.arrow_forward,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _pair('К стене', 'x_plus', 'От стены', 'x_minus'),
        const SizedBox(height: 8),
        _pair('Поворот влево', 'yaw_plus', 'Поворот вправо', 'yaw_minus'),
        const SizedBox(height: 8),
        _pair('Наклон вверх', 'pitch_plus', 'Наклон вниз', 'pitch_minus'),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _connected
              ? () {
            _pressed.clear();
            _sendInput();
            _send({'type': 'reset'});
          }
              : null,
          child: const Text('Сброс'),
        ),
      ],
    ),
  );

  Widget _scene() => FutureBuilder<List<Mesh3D>>(
    future: _models,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: const Text('Не удалось загрузить модели'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _cameraScale = _controller.userScale,
        onScaleUpdate: (details) {
          if (details.pointerCount == 1) {
            _controller.update(
              rotationX:
              (_controller.rotationX - details.focalPointDelta.dy / 2)
                  .clamp(-85.0, 85.0),
              rotationY: _controller.rotationY - details.focalPointDelta.dx / 2,
            );
          } else {
            _controller.update(
              userScale: _cameraScale * details.scale,
              translation: _controller.translation + details.focalPointDelta,
            );
          }
        },
        child: DiTreDi(
          figures: _figures(snapshot.data!),
          bounds: _bounds,
          controller: _controller,
        ),
      );
    },
  );

  Widget _game() => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth >= 700 && size.maxWidth > size.maxHeight) {
        return Row(
          children: [
            Expanded(child: _scene()),
            SizedBox(width: 310, child: _controls()),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: _scene()),
          Expanded(child: _controls()),
        ],
      );
    },
  );

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showForm
              ? 'Lab8'
              : 'Lab8 - Игрок $_slot',
        ),
        actions: _showForm
            ? null
            : [
          IconButton(
            tooltip: 'Подключение',
            onPressed: _settings,
            icon: const Icon(
              Icons.settings,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _showForm
            ? _connectForm()
            : _game(),
      ),
    );
  }
}

Future<List<Mesh3D>> _loadModels() async {
  final parser = ObjParser();
  final racket = Mesh3D(
    await parser.loadFromResources('assets/racket/racket.obj'),
  );
  final secondRacket = Mesh3D(
    racket.faces.map((face) {
      final color = face.color;
      return color != null && color.b > color.r * 1.5 && color.b > color.g
          ? face.copyWith(color: const Color(0xFFEF6C00))
          : face;
    }).toList(),
  );
  return [
    Mesh3D(await parser.loadFromResources('assets/hand/hand.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/index.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/middle.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/ring.obj')),
    Mesh3D(await parser.loadFromResources('assets/hand/pinky.obj')),
    racket,
    secondRacket,
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
    final columns = (a.distanceTo(b) / 2).ceil();
    final rows = (a.distanceTo(d) / 2).ceil();
    vector.Vector3 at(int col, int row) =>
        a + (b - a).scaled(col / columns) + (d - a).scaled(row / rows);
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final q0 = at(col, row), q1 = at(col + 1, row);
        final q2 = at(col + 1, row + 1), q3 = at(col, row + 1);
        faces.add(Face3D.fromVertices(q0, q1, q2, color: color));
        faces.add(Face3D.fromVertices(q0, q2, q3, color: color));
      }
    }
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
