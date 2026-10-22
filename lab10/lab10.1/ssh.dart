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
  late final TextEditingController hostController;
  late final TextEditingController portController;
  late final TextEditingController userController;
  late final TextEditingController passwordController;
  final commandController = TextEditingController();
  final filePathController = TextEditingController();
  final scrollController = ScrollController();
  final terminalLines = <String>[];
  FTPConnect? ftpClient;
  SSHClient? sshClient;
  SSHSession? sshSession;
  StreamSubscription<String>? sshOutputSubscription;
  StreamSubscription<String>? sshErrorSubscription;
  int? sshOutputIndex;
  bool connected = false;
  bool showTerminal = false;
  bool busy = false;

  bool get isFtp => widget.kind == ClientKind.ftp;

  @override
  void initState() {
    super.initState();
    hostController = TextEditingController(text: isFtp ? 'students.yss.su' : 'net11.yss.su');
    portController = TextEditingController(text: isFtp ? '21' : '22');
    userController = TextEditingController(text: isFtp ? 'ftpiu8' : 'root');
    passwordController = TextEditingController(text: isFtp ? '3Ru7yOTA' : 'rqUHO6IG9Du0');
  }

  @override
  void dispose() {
    final ftp = ftpClient;
    if (ftp != null) ftp.disconnect().catchError((Object _) => false);
    sshOutputSubscription?.cancel();
    sshErrorSubscription?.cancel();
    sshSession?.close();
    sshClient?.close();
    hostController.dispose();
    portController.dispose();
    userController.dispose();
    passwordController.dispose();
    commandController.dispose();
    filePathController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void append(String value) {
    if (!mounted || value.trim().isEmpty) return;
    setState(() => terminalLines.add(value.trimRight()));
    scrollToEnd();
  }

  void appendSshOutput(String text) {
    if (!mounted || text.isEmpty) return;
    setState(() {
      if (sshOutputIndex == null) {
        sshOutputIndex = terminalLines.length;
        terminalLines.add(text);
      } else {
        terminalLines[sshOutputIndex!] += text;
      }
    });
    scrollToEnd();
  }

  void scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> connect() async {
    if (busy) return;
    setState(() => busy = true);
    final host = hostController.text.trim();
    try {
      final port = int.parse(portController.text.trim());
      if (isFtp) {
        final ftp = FTPConnect(
          host,
          port: port,
          user: userController.text.trim(),
          pass: passwordController.text,
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
        ftpClient = ftp;
      } else {
        final socket = await SSHSocket.connect(
          host,
          port,
          timeout: const Duration(seconds: 20),
        );
        final ssh = SSHClient(
          socket,
          username: userController.text.trim(),
          onPasswordRequest: () => passwordController.text,
        );
        try {
          await ssh.authenticated.timeout(const Duration(seconds: 30));
          sshSession = await ssh.execute('sh');
        } catch (_) {
          ssh.close();
          rethrow;
        }
        if (!mounted) {
          sshSession?.close();
          ssh.close();
          return;
        }
        sshClient = ssh;
      }
      if (!mounted) return;
      setState(() {
        connected = true;
        showTerminal = true;
        terminalLines.clear();
      });
      append('Подключено к $host:$port');
      if (!isFtp) {
        final session = sshSession!;
        sshOutputIndex = null;
        sshOutputSubscription = session.stdout
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(appendSshOutput, onError: reportCommandError);
        sshErrorSubscription = session.stderr
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(appendSshOutput, onError: reportCommandError);
        unawaited(
          session.done.then<void>(
            (_) {
              if (mounted) setState(() => connected = false);
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(() => connected = false);
              reportCommandError(error);
            },
          ),
        );
      }
    } catch (error) {
      showError('Не удалось подключиться: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> sendCommand() async {
    final command = commandController.text.trim();
    if (!connected || busy || command.isEmpty) return;
    commandController.clear();
    append('> $command');
    sshOutputIndex = null;
    setState(() => busy = true);
    try {
      if (isFtp) {
        append(await ftpCommand(command));
      } else {
        sendSshCommand(command);
      }
    } catch (error) {
      reportCommandError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void reportCommandError(Object error) {
    final timedOut =
        error is TimeoutException ||
        error is FTPConnectException &&
            error.message.toLowerCase().contains('timeout');
    if (isFtp && timedOut) {
      final ftp = ftpClient;
      ftpClient = null;
      connected = false;
      if (ftp != null) {
        unawaited(ftp.disconnect().catchError((Object _) => false));
      }
      append('Превышено время ожидания FTP');
    } else {
      append('Ошибка: $error');
    }
  }

  Future<String> ftpCommand(String input) async {
    final ftp = ftpClient!;
    final split = input.indexOf(RegExp(r'\s'));
    final verb = (split < 0 ? input : input.substring(0, split)).toLowerCase();
    final argument = split < 0 ? '' : input.substring(split + 1).trim();
    if (verb == 'put') return uploadFile(argument);
    if (verb == 'ls' || verb == 'dir' || verb == 'list') {
      final entries = await ftp
          .listDirectoryContent(argument.isEmpty ? null : argument)
          .timeout(const Duration(seconds: 30));
      if (entries.isEmpty) return 'Каталог пуст';
      return entries
          .map(
            (entry) =>
                '${entry.type == FTPEntryType.dir ? 'd' : '-'} '
                '${entry.size?.toString() ?? '-'}  ${entry.name}',
          )
          .join('\n');
    }
    final ftpVerb = switch (verb) {
      'cd' => 'CWD',
      'mkdir' => 'MKD',
      'rmdir' => 'RMD',
      'rm' => 'DELE',
      _ => verb.toUpperCase(),
    };
    final reply = await ftp
        .sendCustomCommand(argument.isEmpty ? ftpVerb : '$ftpVerb $argument')
        .timeout(const Duration(seconds: 30));
    return reply.message;
  }

  void sendSshCommand(String command) {
    sshSession!.write(utf8.encode('$command\n'));
  }

  Future<void> upload() async {
    if (!connected || busy || !isFtp) return;
    setState(() => busy = true);
    try {
      final path = await selectFilePath();
      if (path == null || !mounted) return;
      append('> put $path');
      append(await uploadFile(path));
    } catch (error) {
      reportCommandError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> uploadFile(String path) async {
    var filePath = path.trim();
    if (filePath.length >= 2 &&
        ((filePath.startsWith('"') && filePath.endsWith('"')) ||
            (filePath.startsWith("'") && filePath.endsWith("'")))) {
      filePath = filePath.substring(1, filePath.length - 1);
    }
    final file = File(filePath);
    final success = await ftpClient!
        .uploadFile(file)
        .timeout(const Duration(minutes: 2));
    return success
        ? 'Файл ${file.uri.pathSegments.last} отправлен'
        : 'Отправка не удалась';
  }

  Future<String?> selectFilePath() {
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(dialogContext, filePathController.text.trim());
        }

        return AlertDialog(
          title: const Text('Отправить файл'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: TextFormField(
                controller: filePathController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Путь к файлу'),
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
      title: Text(isFtp ? 'FTP-клиент' : 'SSH-клиент'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: showTerminal ? buildTerminal() : buildForm(),
          ),
        ),
      ),
    ),
  );

  Widget buildForm() => ListView(
    shrinkWrap: true,
    children: [
      TextField(
        controller: hostController,
        decoration: const InputDecoration(labelText: 'Хост'),
      ),
      TextField(
        controller: portController,
        decoration: const InputDecoration(labelText: 'Порт'),
        keyboardType: TextInputType.number,
      ),
      TextField(
        controller: userController,
        decoration: const InputDecoration(labelText: 'Пользователь'),
      ),
      TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Пароль'),
        onSubmitted: (_) => connect(),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: busy ? null : connect,
        child: const Text('Подключиться'),
      ),
    ],
  );

  Widget buildTerminal() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF101820),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: terminalLines.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(
                terminalLines[index],
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
      if (!connected) ...[
        FilledButton(
          onPressed: () => setState(() => showTerminal = false),
          child: const Text('Подключиться заново'),
        ),
        const SizedBox(height: 8),
      ],
      if (isFtp) ...[
        OutlinedButton(
          onPressed: busy || !connected ? null : upload,
          child: const Text('Отправить файл'),
        ),
        const SizedBox(height: 8),
      ],
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: commandController,
              enabled: !busy && connected,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => sendCommand(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: busy || !connected ? null : sendCommand,
            child: const Text('Отправить'),
          ),
        ],
      ),
    ],
  );
}
