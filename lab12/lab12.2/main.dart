import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:usblibforelisey/usblibforelisey.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class ReceivedPhoto {
  final Uint8List bytes;
  final String path;

  ReceivedPhoto(this.bytes, this.path);
}

class _MyAppState extends State<MyApp> {
  String _connectionStatus = 'Unknown';
  String _readData = 'No data received';
  final TextEditingController _textEditingController = TextEditingController();
  bool _listening = false;
  bool _sending = false;
  final List<ReceivedPhoto> _receivedPhotos = [];
  String _serverMode = '';
  String? _deletingPath;
  Completer<bool>? _deleteResult;
  final _usblibforeliseyPlugin = Usblibforelisey();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    String connectionStatus;
    try {
      connectionStatus = await status();
    } catch (e) {
      connectionStatus = 'Some error!';
    }
    if (!mounted) return;
    setState(() {
      _connectionStatus = connectionStatus;
    });
    if (connectionStatus == 'Connected!') {
      unawaited(read());
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) await initPlatformState();
  }

  Future<String> status() async {
    var hasAccessory = await _usblibforeliseyPlugin.hasAccessoryConnected();
    if (!hasAccessory) {
      return 'No devices';
    }
    var hasPermission = await _usblibforeliseyPlugin.hasPermission(0);
    if (!hasPermission) {
      await _usblibforeliseyPlugin.requestPermission(0);
      return 'No permission!';
    }
    final connected = await _usblibforeliseyPlugin.connect(0);
    return connected ? 'Connected!' : 'Connection failed';
  }

  Stream<List<int>> _incomingData() async* {
    while (mounted && _listening) {
      final data = await _usblibforeliseyPlugin.read();
      if (data.isEmpty) throw StateError('Read error');
      yield data;
    }
  }

  Future<void> _writeMessage(Map<String, dynamic> message) async {
    final data = Uint8List.fromList(utf8.encode(jsonEncode(message)));
    for (var offset = 0; offset < data.length; offset += 16384) {
      if (!mounted) return;
      final chunk =
          Uint8List.sublistView(data, offset, min(offset + 16384, data.length));
      if (!await _usblibforeliseyPlugin.write(chunk)) {
        throw StateError('Send error');
      }
    }
    if (!await _usblibforeliseyPlugin.write(Uint8List.fromList([10]))) {
      throw StateError('Send error');
    }
  }

  Future<void> send({bool photo = false}) async {
    if (_sending || _connectionStatus != 'Connected!') return;
    if (!photo && _textEditingController.text.isEmpty) return;
    setState(() => _sending = true);
    try {
      Map<String, dynamic> message;
      String? photoName;
      if (photo) {
        final image =
            await ImagePicker().pickImage(source: ImageSource.gallery);
        if (image == null || !mounted) return;
        photoName = image.name;
        message = {
          'type': 'photo',
          'name': image.name,
          'data': base64Encode(await image.readAsBytes()),
        };
      } else {
        message = {'type': 'text', 'data': _textEditingController.text};
      }
      await _writeMessage(message);
      if (mounted && photoName != null) {
        setState(() => _readData = 'Photo sent: $photoName');
      }
    } catch (_) {
      if (mounted) setState(() => _readData = 'Send error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> deletePhoto(ReceivedPhoto photo) async {
    if (_sending || _serverMode != 'read' || photo.path.isEmpty) return;
    final result = Completer<bool>();
    setState(() {
      _sending = true;
      _deletingPath = photo.path;
      _deleteResult = result;
    });
    try {
      await _writeMessage({'type': 'delete', 'path': photo.path});
      final success = await result.future.timeout(const Duration(seconds: 10));
      if (!success) throw StateError('Delete error');
      if (mounted) {
        setState(() =>
            _receivedPhotos.removeWhere((item) => item.path == photo.path));
      }
    } catch (_) {
      if (mounted) setState(() => _readData = 'Delete error');
    } finally {
      _deleteResult = null;
      _deletingPath = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> read() async {
    if (_listening || _connectionStatus != 'Connected!') return;
    setState(() => _listening = true);
    try {
      final messages = _incomingData()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final message in messages) {
        if (!mounted) return;
        final packet = jsonDecode(message) as Map<String, dynamic>;
        if (packet['type'] == 'photo') {
          final photo = base64Decode(packet['data'] as String);
          if (photo.isEmpty) {
            throw const FormatException('Invalid received data');
          }
          final path = packet['path'] as String? ?? '';
          setState(() => _receivedPhotos.add(ReceivedPhoto(photo, path)));
        } else if (packet['type'] == 'text') {
          setState(() => _readData = packet['data'] as String);
        } else if (packet['type'] == 'mode') {
          setState(() => _serverMode = packet['data'] as String);
        } else if (packet['type'] == 'delete_result') {
          if (packet['path'] == _deletingPath &&
              _deleteResult != null &&
              !_deleteResult!.isCompleted) {
            _deleteResult!.complete(packet['ok'] == true);
          }
        } else {
          throw const FormatException('Invalid received data');
        }
      }
    } catch (_) {
      if (_deleteResult != null && !_deleteResult!.isCompleted) {
        _deleteResult!.complete(false);
      }
      if (mounted) {
        setState(() {
          _readData = 'Read error';
          _serverMode = '';
        });
      }
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  void dispose() {
    _listening = false;
    if (_deleteResult != null && !_deleteResult!.isCompleted) {
      _deleteResult!.complete(false);
    }
    _textEditingController.dispose();
    unawaited(_usblibforeliseyPlugin.disconnect().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _connectionStatus == 'Connected!' && !_sending;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Connection status: $_connectionStatus\n'),
              Text('PC mode: ${_serverMode.isEmpty ? 'Unknown' : _serverMode}'),
              TextField(
                controller: _textEditingController,
                decoration: const InputDecoration(
                  hintText: 'Enter your message',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: canSend ? () => send() : null,
                    child: const Text('Send'),
                  ),
                  ElevatedButton(
                    onPressed: canSend ? () => send(photo: true) : null,
                    child: const Text('Send photo'),
                  ),
                  ElevatedButton(
                    onPressed: _connectionStatus == 'Connected!' && !_listening
                        ? read
                        : null,
                    child: const Text('Listen'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Reader: $_readData',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.only(top: 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _receivedPhotos.length,
                  itemBuilder: (context, index) {
                    final photo = _receivedPhotos[index];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          photo.bytes,
                          fit: BoxFit.cover,
                          cacheWidth: 600,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                  child: Text('Unable to display photo')),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton.filled(
                            tooltip: 'Delete on PC (read)',
                            onPressed: _serverMode == 'read' &&
                                    !_sending &&
                                    photo.path.isNotEmpty
                                ? () => deletePhoto(photo)
                                : null,
                            icon: const Icon(Icons.delete),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
