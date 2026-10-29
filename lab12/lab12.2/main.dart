import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  String _connectionStatus = 'Ожидание USB-устройства';
  String _readData = 'Нет данных';
  String _error = '';
  bool _connected = false;
  bool _listening = false;
  bool _permissionRequested = false;
  final _textEditingController = TextEditingController();
  final _usblibforeliseyPlugin = Usblibforelisey();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    while (mounted) {
      String connectionStatus;
      try {
        connectionStatus = await status();
      } catch (e) {
        connectionStatus = 'Ошибка подключения: $e';
      }
      if (!mounted) return;
      setState(() {
        _connectionStatus = connectionStatus;
        _connected = connectionStatus == 'Подключено';
      });
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<String> status() async {
    final hasAccessory = await _usblibforeliseyPlugin.hasAccessoryConnected();
    if (!hasAccessory) {
      _permissionRequested = false;
      if (_connected) await _usblibforeliseyPlugin.disconnect();
      return 'Ожидание USB-устройства';
    }

    final hasPermission = await _usblibforeliseyPlugin.hasPermission(0);
    if (!hasPermission) {
      if (_permissionRequested) {
        return 'Нет разрешения. Переподключите USB-кабель';
      }
      _permissionRequested = true;
      final granted = await _usblibforeliseyPlugin.requestPermission(0);
      if (!granted) return 'Нет разрешения. Переподключите USB-кабель';
    }

    final connected = await _usblibforeliseyPlugin.connect(0);
    return connected ? 'Подключено' : 'Не удалось подключиться';
  }

  Future<void> send() async {
    final text = _textEditingController.text;
    if (!_connected || text.isEmpty) return;
    try {
      final sent = await _usblibforeliseyPlugin.write(
        Uint8List.fromList(utf8.encode('$text\n')),
      );
      if (!sent) throw StateError('Сообщение не отправлено');
      if (mounted) setState(() => _error = '');
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка отправки: $e');
    }
  }

  Stream<List<int>> _incomingData() async* {
    while (mounted && _listening) {
      final data = await _usblibforeliseyPlugin.read();
      if (data.isEmpty) throw StateError('USB-соединение закрыто');
      yield data;
    }
  }

  Future<void> read() async {
    if (!_connected || _listening) return;
    setState(() {
      _listening = true;
      _error = '';
    });
    try {
      final messages = _incomingData()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final message in messages) {
        if (!mounted) return;
        setState(() => _readData = message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка чтения: $e');
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
        appBar: AppBar(title: const Text('Обмен по USB')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Состояние: $_connectionStatus'),
                const SizedBox(height: 16),
                TextField(
                  controller: _textEditingController,
                  decoration: const InputDecoration(
                    hintText: 'Введите сообщение',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _connected ? send : null,
                  child: const Text('Отправить (Send)'),
                ),
                ElevatedButton(
                  onPressed: _connected && !_listening ? read : null,
                  child: Text(
                    _listening ? 'Чтение включено' : 'Слушать (Listen)',
                  ),
                ),
                const SizedBox(height: 20),
                SelectableText(
                  'Получено: $_readData',
                  style: const TextStyle(fontSize: 24),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
