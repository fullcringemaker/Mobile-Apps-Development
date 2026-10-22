import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'mail.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: MailingApp()),
);

class MailingApp extends StatefulWidget {
  const MailingApp({super.key});
  @override
  State<MailingApp> createState() => _MailingAppState();
}

class _MailingAppState extends State<MailingApp> with WidgetsBindingObserver {
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _text = TextEditingController();
  final _delay = TextEditingController(text: '300');
  final _mail = Mail();
  final _receiver = GlobalKey();
  static const _categories = {
    'name': 'Имена',
    'surname': 'Фамилии',
    'mail': 'Почты',
  };
  static const _cardSize = Size(100, 72);
  late SharedPreferences _preferences;
  List<Map<String, dynamic>> _subscribers = [], _letters = [], _recipients = [];
  Set<String> _hidden = {};
  String? _category;
  String _error = '';
  int _errorPage = 0;
  int _page = 0, _recipientIndex = 0, _remaining = 0;
  bool _randomDelay = true,
      _loading = true,
      _inboxLoading = false,
      _sending = false,
      _mailInFlight = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      _delay.text = '${_preferences.getInt('delay') ?? 300}';
      _randomDelay = _preferences.getBool('randomDelay') ?? true;
      _hidden = (_preferences.getStringList('hidden') ?? []).toSet();
      await createTable();
      await _readSubscribers();
    } catch (error) {
      _showError(error);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showError(Object error, {int? page}) {
    if (mounted) {
      setState(() {
        _error = error.toString();
        _errorPage = page ?? _page;
      });
    }
  }

  Future<void> _readSubscribers() async {
    final people = await getSubscribers();
    if (mounted) setState(() => _subscribers = people);
  }

  Future<void> _selectCategory(String category) async {
    setState(() {
      _category = category;
      _loading = true;
      _error = '';
    });
    try {
      await _readSubscribers();
    } catch (error) {
      _showError(error);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    try {
      await addSubscriber(_name.text, _surname.text, _email.text);
      _name.clear();
      _surname.clear();
      _email.clear();
      await _readSubscribers();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _readInbox() async {
    if (_inboxLoading) return;
    setState(() {
      _inboxLoading = true;
      _error = '';
    });
    try {
      final letters = await _mail.inbox(_hidden);
      if (mounted) {
        setState(
          () => _letters = letters
              .where((letter) => !_hidden.contains(letter['key']))
              .toList(),
        );
      }
    } catch (error) {
      _showError(error, page: 2);
    }
    if (mounted) setState(() => _inboxLoading = false);
  }

  Future<void> _startMailing() async {
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      await _readSubscribers();
      _recipients = _subscribers.where((s) => s['ifsend'] != 1).toList();
      _recipientIndex = 0;
      await _sendNext();
    } catch (error) {
      _stopMailing();
      _showError(error);
    }
  }

  Future<void> _sendNext() async {
    if (!_sending) return;
    if (_recipientIndex == _recipients.length) {
      _stopMailing();
      return;
    }
    setState(() => _mailInFlight = true);
    try {
      final subscriber = _recipients[_recipientIndex];
      await _mail.send(subscriber, _subject.text, _text.text);
      await markSent(subscriber['id'] as int);
      _recipientIndex++;
      await _readSubscribers();
      if (!_sending || _recipientIndex == _recipients.length) {
        _stopMailing();
        return;
      }
      setState(
        () => _remaining =
            int.parse(_delay.text) + (_randomDelay ? Random().nextInt(301) : 0),
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remaining > 0) setState(() => _remaining--);
        if (_remaining == 0) {
          timer.cancel();
          _sendNext();
        }
      });
    } catch (error) {
      _stopMailing();
      _showError(error);
    } finally {
      if (mounted) setState(() => _mailInFlight = false);
    }
  }

  void _stopMailing() {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _sending = false;
        _remaining = 0;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopMailing();
    }
  }

  Widget _card(String category) => Material(
    child: SizedBox.fromSize(
      size: _cardSize,
      child: Card(
        margin: EdgeInsets.zero,
        child: Center(child: Text(_categories[category]!)),
      ),
    ),
  );

  Widget _cards() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _categories.keys
            .where((category) => category != _category)
            .map(
              (category) => Draggable<String>(
                data: category,
                maxSimultaneousDrags: _loading ? 0 : 1,
                rootOverlay: true,
                feedback: _card(category),
                childWhenDragging: const SizedBox(width: 100, height: 72),
                onDragEnd: (details) {
                  final box =
                      _receiver.currentContext!.findRenderObject()!
                          as RenderBox;
                  final target = box.localToGlobal(Offset.zero) & box.size;
                  final card = details.offset & _cardSize;
                  if (card.left <= target.right &&
                      card.right >= target.left &&
                      card.top <= target.bottom &&
                      card.bottom >= target.top) {
                    _selectCategory(category);
                  }
                },
                child: _card(category),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 16),
      Container(
        key: _receiver,
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Нужные данные'),
            if (_category != null) _card(_category!),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_category != null) ...[
        Text(
          _categories[_category]!,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (!_loading)
          ..._subscribers.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${s[_category]}'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('${s['name']} ${s['surname']}'),
                  content: Text('${s['mail']}'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ],
  );

  Widget _subscribersPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Имя'),
      ),
      TextField(
        controller: _surname,
        decoration: const InputDecoration(labelText: 'Фамилия'),
      ),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: _add, child: const Text('Добавить абонента')),
      const SizedBox(height: 24),
      _cards(),
    ],
  );

  Widget _composePage() {
    final sent = _subscribers.where((s) => s['ifsend'] == 1).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _subject,
          enabled: !_sending,
          decoration: const InputDecoration(labelText: 'Тема письма'),
        ),
        TextField(
          controller: _text,
          enabled: !_sending,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Текст письма'),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _mailInFlight
              ? null
              : _sending
              ? _stopMailing
              : _startMailing,
          child: Text(_sending ? 'Остановить' : 'Отправить неотправленным'),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: _subscribers.isEmpty ? 0 : sent / _subscribers.length,
          minHeight: 22,
          backgroundColor: Colors.grey.shade300,
          color: Colors.green,
        ),
        const SizedBox(height: 8),
        Text('Отправлено: $sent из ${_subscribers.length}'),
        if (_sending)
          Text(
            _remaining > 0
                ? 'Следующее письмо через $_remaining сек.'
                : 'Отправка…',
          ),
        const SizedBox(height: 16),
        ..._subscribers.map(
          (s) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${s['name']} ${s['surname']}'),
            subtitle: Text('${s['mail']}'),
            trailing: Tooltip(
              message: s['ifsend'] == 1 ? 'Отправлено' : 'Не отправлено',
              child: Container(
                width: 16,
                height: 16,
                color: s['ifsend'] == 1 ? Colors.green : Colors.grey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inboxPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_inboxLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
      if (!_inboxLoading &&
          _letters.isEmpty &&
          !(_errorPage == 2 && _error.isNotEmpty))
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Входящих писем нет.'),
        ),
      ..._letters.map(
        (letter) => ListTile(
          title: Text('${letter['subject']}'),
          subtitle: Text('${letter['from']}'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('${letter['subject']}'),
              content: SingleChildScrollView(
                child: SelectableText('${letter['body']}'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
          trailing: TextButton(
            onPressed: () async {
              _hidden.add(letter['key'] as String);
              await _preferences.setStringList('hidden', _hidden.toList());
              await _readInbox();
            },
            child: const Text('Удалить'),
          ),
        ),
      ),
    ],
  );

  Widget _settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _delay,
        enabled: !_sending,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Глобальный интервал, секунд',
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _randomDelay,
        title: const Text('Добавлять случайные 0–5 минут'),
        onChanged: _sending
            ? null
            : (value) => setState(() => _randomDelay = value),
      ),
      ElevatedButton(
        onPressed: () async {
          await _preferences.setInt('delay', int.parse(_delay.text));
          await _preferences.setBool('randomDelay', _randomDelay);
        },
        child: const Text('Сохранить настройки'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(const ['Абоненты', 'Рассылка', 'Inbox', 'Настройки'][_page]),
      actions: [
        TextButton(
          onPressed: () async {
            try {
              setState(() => _error = '');
              if (_page == 2) {
                await _readInbox();
              } else {
                await _readSubscribers();
              }
            } catch (error) {
              _showError(error);
            }
          },
          child: const Text('Обновить'),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty && _errorPage == _page)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          switch (_page) {
            0 => _subscribersPage(),
            1 => _composePage(),
            2 => _inboxPage(),
            _ => _settingsPage(),
          },
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Row(
        children: [
          for (var page = 0; page < 4; page++)
            Expanded(
              child: TextButton(
                onPressed: () {
                  setState(() => _page = page);
                  if (page == 2) _readInbox();
                },
                style: TextButton.styleFrom(
                  foregroundColor: _page == page
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
                child: Text(
                  const ['Абоненты', 'Рассылка', 'Inbox', 'Настройки'][page],
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final field in [_name, _surname, _email, _subject, _text, _delay]) {
      field.dispose();
    }
    super.dispose();
  }
}
