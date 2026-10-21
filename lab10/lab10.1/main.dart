import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';

void main() => runApp(const ClientApp());

enum ClientKind { ftp, ssh }

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FTP и SSH клиент',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF206B91)),
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ClientPage(kind: ClientKind.ftp),
                  ),
                ),
                child: const Text('FTP-клиент'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ClientPage(kind: ClientKind.ssh),
                  ),
                ),
                child: const Text('SSH-клиент'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ClientPage extends StatefulWidget {
  const ClientPage({required this.kind, super.key});
  final ClientKind kind;

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _password;
  final _command = TextEditingController();
  final _filePath = TextEditingController();
  final _scroll = ScrollController();
  final _lines = <String>[];
  FTPConnect? _ftp;
  SSHClient? _ssh;
  bool _connected = false;
  bool _showTerminal = false;
  bool _busy = false;

  bool get _isFtp => widget.kind == ClientKind.ftp;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(
      text: _isFtp ? 'students.yss.su' : 'net11.yss.su',
    );
    _port = TextEditingController(text: _isFtp ? '21' : '22');
    _user = TextEditingController(text: _isFtp ? 'ftpiu8' : 'root');
    _password = TextEditingController(
      text: _isFtp ? '3Ru7yOTA' : 'rqUHO6IG9Du0',
    );
  }

  @override
  void dispose() {
    final ftp = _ftp;
    if (ftp != null) ftp.disconnect().catchError((Object _) => false);
    _ssh?.close();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _command.dispose();
    _filePath.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _append(String value) {
    if (!mounted || value.trim().isEmpty) return;
    setState(() => _lines.add(value.trimRight()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _connect() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final host = _host.text.trim();
    final port = int.parse(_port.text.trim());
    try {
      if (_isFtp) {
        final ftp = FTPConnect(
          host,
          port: port,
          user: _user.text.trim(),
          pass: _password.text,
          showLog: false,
          timeout: 20,
          supportIPV6: true,
        );
        if (!await ftp.connect()) {
          throw StateError('Сервер отклонил подключение');
        }
        if (!mounted) {
          await ftp.disconnect();
          return;
        }
        _ftp = ftp;
      } else {
        final socket = await SSHSocket.connect(
          host,
          port,
          timeout: const Duration(seconds: 20),
        );
        final ssh = SSHClient(
          socket,
          username: _user.text.trim(),
          onPasswordRequest: () => _password.text,
        );
        try {
          await ssh.authenticated.timeout(const Duration(seconds: 30));
        } catch (_) {
          ssh.close();
          rethrow;
        }
        if (!mounted) {
          ssh.close();
          return;
        }
        _ssh = ssh;
      }
      if (!mounted) return;
      setState(() {
        _connected = true;
        _showTerminal = true;
        _lines.clear();
      });
      _append('Подключено к $host:$port');
    } catch (error) {
      _showError('Не удалось подключиться: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendCommand() async {
    final command = _command.text.trim();
    if (!_connected || _busy || command.isEmpty) return;
    _command.clear();
    _append('> $command');
    setState(() => _busy = true);
    try {
      _append(
        _isFtp
            ? await _ftpCommand(command).timeout(const Duration(seconds: 30))
            : await _sshCommand(command),
      );
    } catch (error) {
      _reportCommandError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reportCommandError(Object error) {
    final timedOut =
        error is TimeoutException ||
        error is FTPConnectException &&
            error.message.toLowerCase().contains('timeout');
    if (_isFtp && timedOut) {
      final ftp = _ftp;
      _ftp = null;
      _connected = false;
      if (ftp != null) {
        unawaited(ftp.disconnect().catchError((Object _) => false));
      }
      _append(
        'Превышено время ожидания FTP',
      );
    } else {
      _append('Ошибка: $error');
    }
  }

  Future<String> _ftpCommand(String input) async {
    final ftp = _ftp!;
    final split = input.indexOf(' ');
    final verb = (split < 0 ? input : input.substring(0, split)).toLowerCase();
    final argument = split < 0 ? '' : input.substring(split + 1).trim();
    if (verb == 'ls' || verb == 'dir' || verb == 'list') {
      final entries = await ftp.listDirectoryContent(
        argument.isEmpty ? null : argument,
      );
      if (entries.isEmpty) return 'Каталог пуст';
      return entries
          .map(
            (entry) =>
                '${entry.type == FTPEntryType.dir ? 'd' : '-'} '
                '${entry.size?.toString() ?? '-'}  ${entry.name}',
          )
          .join('\n');
    }
    if ({'put', 'get', 'retr', 'stor'}.contains(verb)) {
      return 'Для отправки файла используйте кнопку «Отправить файл».';
    }
    if ({'mlsd', 'nlst'}.contains(verb)) {
      return 'Для просмотра каталога используйте ls.';
    }
    final ftpVerb = switch (verb) {
      'cd' => 'CWD',
      'mkdir' => 'MKD',
      'rmdir' => 'RMD',
      'rm' => 'DELE',
      _ => verb.toUpperCase(),
    };
    final reply = await ftp.sendCustomCommand(
      argument.isEmpty ? ftpVerb : '$ftpVerb $argument',
    );
    return reply.message;
  }

  Future<String> _sshCommand(String command) async {
    final output = await _ssh!.run(command);
    return utf8.decode(output, allowMalformed: true);
  }

  Future<void> _upload() async {
    if (!_connected || _busy || !_isFtp) return;
    setState(() => _busy = true);
    try {
      final path = await _selectFilePath();
      if (path == null || !mounted) return;
      final file = File(path);
      _append('> put "$path"');
      if (!await file.exists()) {
        throw FileSystemException('Файл не найден', path);
      }
      final success = await _ftp!
          .uploadFile(file)
          .timeout(const Duration(minutes: 2));
      _append(
        success
            ? 'Файл ${file.uri.pathSegments.last} отправлен'
            : 'Отправка не удалась',
      );
    } catch (error) {
      _reportCommandError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _selectFilePath() {
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (!formKey.currentState!.validate()) return;
          var path = _filePath.text.trim();
          if (path.length >= 2 && path.startsWith('"') && path.endsWith('"')) {
            path = path.substring(1, path.length - 1);
          }
          Navigator.pop(dialogContext, path);
        }

        return AlertDialog(
          title: const Text('Отправить файл'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: TextFormField(
                controller: _filePath,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Путь к файлу',
                  hintText: r'C:\Users\user\Documents\file.txt',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Укажите путь к файлу'
                    : null,
                onFieldSubmitted: (_) => submit(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(onPressed: submit, child: const Text('Отправить')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leadingWidth: 90,
      leading: TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Назад'),
      ),
      title: Text(_isFtp ? 'FTP-клиент' : 'SSH-клиент'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _showTerminal ? _buildTerminal() : _buildForm(),
          ),
        ),
      ),
    ),
  );

  Widget _buildForm() => Form(
    key: _formKey,
    child: ListView(
      shrinkWrap: true,
      children: [
        TextFormField(
          controller: _host,
          decoration: const InputDecoration(labelText: 'Хост'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Укажите хост' : null,
        ),
        TextFormField(
          controller: _port,
          decoration: const InputDecoration(labelText: 'Порт'),
          keyboardType: TextInputType.number,
          validator: (value) {
            final port = int.tryParse(value?.trim() ?? '');
            return port == null || port < 1 || port > 65535
                ? 'Укажите порт от 1 до 65535'
                : null;
          },
        ),
        TextFormField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'Пользователь'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Укажите пользователя'
              : null,
        ),
        TextFormField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Пароль'),
          onFieldSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: Text(_busy ? 'Подключение...' : 'Подключиться'),
        ),
      ],
    ),
  );

  Widget _buildTerminal() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF101820),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _lines.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(
                _lines[index],
                style: const TextStyle(
                  color: Color(0xFFE8F4ED),
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (!_connected) ...[
        FilledButton(
          onPressed: () => setState(() => _showTerminal = false),
          child: const Text('Подключиться заново'),
        ),
        const SizedBox(height: 8),
      ],
      if (_isFtp) ...[
        OutlinedButton(
          onPressed: _busy || !_connected ? null : _upload,
          child: const Text('Отправить файл'),
        ),
        const SizedBox(height: 8),
      ],
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _command,
              enabled: !_busy && _connected,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Введите команду',
                isDense: true,
              ),
              onSubmitted: (_) => _sendCommand(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy || !_connected ? null : _sendCommand,
            child: const Text('Отправить'),
          ),
        ],
      ),
    ],
  );
}
