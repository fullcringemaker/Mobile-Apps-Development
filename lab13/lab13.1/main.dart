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
    try {
      final bool result = await platform.invokeMethod('initializeBluetooth');
      if (!mounted) return;
      setState(() {
        _isConnected = result;
        _statusMessage = result ? 'Connected' : 'Waiting for connection...';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error: ${e.message}';
      });
    }
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
              _statusMessage = event['message'] as String? ??
                  (event['connected'] ? 'Connected' : 'Disconnected');
              _scrollToBottom();
            });
          } else if (event['type'] == 'error') {
            setState(() {
              _isConnected = false;
              _statusMessage = 'Error: ${event['message']}';
            });
          }
        }
      },
      onError: (dynamic error) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Error: $error';
        });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Messenger'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
