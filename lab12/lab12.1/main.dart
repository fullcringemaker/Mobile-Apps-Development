import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:usblibforelisey/usblibforelisey.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _connectionStatus = 'Unknown';
  String _readData = 'No data received';
  final TextEditingController _textEditingController = TextEditingController();
  bool _listening = false;
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
      if (data.isEmpty) throw StateError('USB connection closed');
      yield data;
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
        setState(() => _readData = message);
      }
    } catch (e) {
      if (mounted) setState(() => _readData = 'Read error: $e');
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  void dispose() {
    _listening = false;
    _textEditingController.dispose();
    unawaited(_usblibforeliseyPlugin.disconnect().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: [
              Text('Connection status: $_connectionStatus\n'),
              TextField(
                controller: _textEditingController,
                decoration: const InputDecoration(
                  hintText: 'Enter your message',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _connectionStatus != 'Connected!'
                    ? null
                    : () async {
                        if (_textEditingController.text.isEmpty) {
                          return;
                        }
                        try {
                          await _usblibforeliseyPlugin.write(Uint8List.fromList(
                              utf8.encode('${_textEditingController.text}\n')));
                        } catch (e) {
                          if (mounted) {
                            setState(() => _readData = 'Send error: $e');
                          }
                        }
                        return;
                      },
                child: const Text('Send'),
              ),
              ElevatedButton(
                onPressed: _connectionStatus == 'Connected!' && !_listening
                    ? read
                    : null,
                child: const Text('Listen'),
              ),
              const SizedBox(height: 20),
              Text(
                'Reader: $_readData',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
