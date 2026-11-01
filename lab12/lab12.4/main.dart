import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
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
    String _connectionStatus = 'Unknown';
    String _readData = 'No data received';
    bool _listening = false;
    bool _sending = false;
    final _textEditingController = TextEditingController();
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
        } catch (_) {
            connectionStatus = 'Connection error';
        }
        if (!mounted) return;
        setState(() => _connectionStatus = connectionStatus);
        if (connectionStatus == 'Connected!') {
            unawaited(read());
            return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        if (mounted) await initPlatformState();
    }

    Future<String> status() async {
        if (!await _usblibforeliseyPlugin.hasAccessoryConnected()) {
            return 'No devices';
        }
        if (!await _usblibforeliseyPlugin.hasPermission(0)) {
            await _usblibforeliseyPlugin.requestPermission(0);
            return 'No permission!';
        }
        final connected = await _usblibforeliseyPlugin.connect(0);
        return connected ? 'Connected!' : 'Connection failed';
    }

    Future<void> send() async {
        final text = _textEditingController.text;
        if (_sending || _connectionStatus != 'Connected!' || text.isEmpty) return;
        setState(() => _sending = true);
        try {
            final data = Uint8List.fromList(utf8.encode(text));
            for (var offset = 0; offset < data.length; offset += 16384) {
                if (!mounted) return;
                final chunk = Uint8List.sublistView(data, offset, min(offset + 16384, data.length));
                if (!await _usblibforeliseyPlugin.write(chunk)) {
                    throw StateError('Send error');
                }
            }
            if (!await _usblibforeliseyPlugin.write(Uint8List.fromList([10]))) {
                throw StateError('Send error');
            }
        } catch (_) {
            if (mounted) setState(() => _readData = 'Send error');
        } finally {
            if (mounted) setState(() => _sending = false);
        }
    }

    Stream<List<int>> _incomingData() async* {
        while (mounted && _listening) {
            final data = await _usblibforeliseyPlugin.read();
            if (data.isEmpty) throw StateError('Read error');
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
        } catch (_) {
            if (mounted) setState(() => _readData = 'Read error');
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
                appBar: AppBar(title: const Text('lab12server')),
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                onPressed: _connectionStatus == 'Connected!' && !_sending ? send : null,
                                child: const Text('Send'),
                            ),
                            const SizedBox(height: 20),
                            Text(
                                'Reader: $_readData',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }
}
