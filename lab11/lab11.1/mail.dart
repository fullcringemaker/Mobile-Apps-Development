import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:html/parser.dart' as html;

class Mail {
  static const address = 'dmtrfmnk10@mail.ru';
  static const _password = '6mp6YB6liRw5m4SjRxL4';

  Future<void> send(Map<String, dynamic> subscriber, String subject, String text) async {
    final recipient = MailAddress(null, (subscriber['mail'] as String).trim());
    final client = SmtpClient('mail.ru');
    try {
      await client.connectToServer('smtp.mail.ru', 465, isSecure: true);
      await client.ehlo();
      await client.authenticate(address, _password, AuthMechanism.login);
      final greeting = 'Привет, ${subscriber['name']} ${subscriber['surname']}.';
      const escape = HtmlEscape(HtmlEscapeMode.element);
      final body = escape.convert(text).replaceAll('\n', '<br>');
      final builder =
          MessageBuilder.prepareMultipartAlternativeMessage(
              plainText: '$greeting\n\n$subject\n\n$text',
              htmlText:
                  '<html><head><meta charset="utf-8"></head><body>'
                  '<h2>${escape.convert(greeting)}</h2>'
                  '<h3>${escape.convert(subject)}</h3>'
                  '<p>$body</p></body></html>',
              transferEncoding: TransferEncoding.base64,
            )
            ..from = [MailAddress(null, address)]
            ..to = [recipient]
            ..subject = subject;
      await client.sendMessage(
        builder.buildMimeMessage(),
        recipients: [recipient],
      );
    } on SmtpException catch (error) {
      throw Exception(
        'Не удалось отправить на ${recipient.email}: ${error.message}',
      );
    } on SocketException {
      throw Exception('Нет соединения с почтовым сервером.');
    } finally {
      if (client.isConnected) {
        try {
          await client.disconnect();
        } on SocketException {
          // The server may already have closed the connection.
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> inbox(Set<String> hidden) async {
    final client = ImapClient(
      defaultResponseTimeout: const Duration(seconds: 60),
    );
    try {
      await client.connectToServer('imap.mail.ru', 993, isSecure: true);
      await client.login(address, _password);
      final box = await client.selectInbox();
      final search = await client.uidSearchMessages(
        searchCriteria: 'NOT DELETED',
      );
      final ids = (search.matchingSequence?.toList() ?? [])
              .where((id) => !hidden.contains('${box.uidValidity}:$id'))
              .toList()
            ..sort((a, b) => b.compareTo(a));
      if (ids.isEmpty) return [];
      final result = await client.uidFetchMessages(
        MessageSequence.fromIds(ids.take(10).toList(), isUid: true),
        '(UID BODY.PEEK[])',
      );
      final messages = result.messages
        ..sort((a, b) => b.uid!.compareTo(a.uid!));
      return messages
          .map(
            (message) => {
              'key': '${box.uidValidity}:${message.uid}',
              'from': message
                  .decodeSender()
                  .map((sender) => sender.email)
                  .join(', '),
              'subject': message.decodeSubject() ?? '(Без темы)',
              'body':
                  message.decodeTextPlainPart() ??
                  html.parse(message.decodeTextHtmlPart() ?? '').body?.text ??
                  '',
            },
          )
          .toList();
    } finally {
      try {
        if (client.isLoggedIn) await client.logout();
      } finally {
        if (client.isConnected) await client.disconnect();
      }
    }
  }
}
