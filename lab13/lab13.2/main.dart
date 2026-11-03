import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Messenger',
      theme: ThemeData(
        useMaterial3: false,
      ),
      home: const BluetoothMessengerPage(),
    );
  }
}

class BluetoothMessengerPage extends StatefulWidget {
  const BluetoothMessengerPage({super.key});

  @override
  State<BluetoothMessengerPage> createState() => _BluetoothMessengerPageState();
}

class _BluetoothMessengerPageState extends State<BluetoothMessengerPage> {
  static const platform = MethodChannel('bluetooth.messenger/channel');
  
  final TextEditingController _messageController = TextEditingController();
  final List<String> _receivedMessages = [];
  final ScrollController _scrollController = ScrollController();
  
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isScanning = false;
  bool _isPairing = false;
  bool _isLoadingDevices = false;
  bool _deviceReady = false;
  final List<Map<String, dynamic>> _devices = [];
  String? _selectedAddress;
  String? _selectedName;
  String _statusMessage = 'Disconnected';
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _startListeningForMessages();
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    setState(() {
      _isLoadingDevices = true;
      _statusMessage = 'Поиск устройств Bluetooth...';
    });
    try {
      await platform.invokeMethod<bool>('initializeBluetooth');
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Bluetooth error');
    } finally {
      if (mounted) setState(() { _isLoadingDevices = false; });
    }
  }

  Future<void> _selectDevice(Map<String, dynamic> device) async {
    setState(() {
      _selectedAddress = device['address'] as String;
      _selectedName = device['name'] as String;
      _deviceReady = false;
      _isPairing = device['paired'] != true;
      _statusMessage = _isPairing
          ? 'Подтвердите код сопряжения на обоих устройствах.'
          : 'Выбор устройства...';
    });
    try {
      await platform.invokeMethod<void>('selectDevice', {'address': _selectedAddress});
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Device selection failed');
    }
  }

  Future<void> _connectToServer() async {
    if (!_deviceReady || _isPairing || _isConnecting) return;
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Подключение к серверу...';
    });
    try {
      await platform.invokeMethod<void>('connectToServer');
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Connection failed');
    }
  }

  Future<void> _disconnect() async {
    FocusScope.of(context).unfocus();
    try {
      await platform.invokeMethod<void>('disconnect');
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Disconnect failed');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _isConnecting = false;
      _isPairing = false;
      _isScanning = false;
      _statusMessage = 'Error: $message';
    });
  }

  void _startListeningForMessages() {
    const EventChannel eventChannel = EventChannel('bluetooth.messenger/events');
    _messageSubscription = eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (!mounted) return;
        if (event is Map) {
          if (event['type'] == 'message') {
            setState(() {
              _receivedMessages.add(event['data']);
              _scrollToBottom();
            });
          } else if (event['type'] == 'connection') {
            setState(() {
              _isConnected = event['connected'];
              _isConnecting = event['connecting'] == true;
              _statusMessage = event['message'] as String? ??
                  (event['connected'] ? 'Connected' : 'Disconnected');
              _scrollToBottom();
            });
          } else if (event['type'] == 'devices') {
            setState(() {
              _devices
                ..clear()
                ..addAll((event['devices'] as List).map(
                    (dynamic item) => Map<String, dynamic>.from(item as Map)));
            });
          } else if (event['type'] == 'scan') {
            setState(() {
              _isScanning = event['scanning'] == true;
              if (!_deviceReady && !_isPairing && !_isConnecting && !_isConnected) {
                _statusMessage = _isScanning ? 'Поиск устройств Bluetooth...'
                    : 'Нажмите на устройство для выбора или сопряжения.';
              }
            });
          } else if (event['type'] == 'selection') {
            setState(() {
              final address = event['address'] as String;
              _selectedAddress = address.isEmpty ? null : address;
              _selectedName = event['name'] as String;
              _deviceReady = event['ready'] == true;
              _isPairing = event['pairing'] == true;
              _statusMessage = event['message'] as String;
            });
          } else if (event['type'] == 'error') {
            _setError(event['message'] as String);
          }
        }
      },
      onError: (dynamic error) {
        _setError('$error');
      },
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final String message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      final bool success = await platform.invokeMethod('sendMessage', {'message': message});
      if (!mounted) return;
      if (success) {
        setState(() {
          _messageController.clear();
          _scrollToBottom();
        });
      } else {
        _showSnackBar('Failed to send message');
      }
    } on PlatformException catch (e) {
      if (mounted) _showSnackBar('Error: ${e.message}');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDevices = !_isConnected && MediaQuery.of(context).viewInsets.bottom == 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Messenger'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDevices) ...[
              Row(
                children: [
                  const Expanded(child: Text('Устройства Bluetooth')),
                  TextButton(
                    onPressed: _isScanning || _isLoadingDevices || _isPairing || _isConnecting
                        ? null : _initializeBluetooth,
                    child: Text(_isScanning ? 'Поиск...' : 'Найти устройства'),
                  ),
                ],
              ),
              if (_isScanning) const LinearProgressIndicator(),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(border: Border.all()),
                  child: _devices.isEmpty
                      ? const Center(child: Text('Найденные устройства появятся здесь'))
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            final selected = device['address'] == _selectedAddress;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              title: Text(device['name'] as String),
                              subtitle: Text('${device['address']} - '
                                  '${device['paired'] == true ? 'Сопряжено' : 'Новое устройство'}'),
                              trailing: selected ? const Icon(Icons.check_circle) : null,
                              onTap: _isConnecting ? null : () => _selectDevice(device),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_selectedAddress != null)
              Text('Устройство: $_selectedName', maxLines: 1, overflow: TextOverflow.ellipsis),
            ElevatedButton(
              onPressed: _isConnected || _isConnecting ? _disconnect
                  : (_deviceReady && !_isPairing ? _connectToServer : null),
              child: Text(_isConnecting ? 'Отменить подключение'
                  : _isConnected ? 'Отключиться от сервера' : 'Подключиться к серверу'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
              enabled: _isConnected,
              onSubmitted: (_) => _sendMessage(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isConnected ? _sendMessage : null,
              child: const Text('Send'),
            ),
            const SizedBox(height: 16),
            Text(
              'Status: $_statusMessage',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Messages:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(),
                ),
                child: _receivedMessages.isEmpty
                    ? const Center(
                        child: Text('No messages yet'),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _receivedMessages.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(_receivedMessages[index]),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
