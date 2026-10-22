import 'package:mysql1/mysql1.dart';

Future<T> _query<T>(Future<T> Function(MySqlConnection) action) async {
  final connection = await MySqlConnection.connect(
    ConnectionSettings(
      host: 'students.yss.su',
      port: 3306,
      user: 'iu9mobile',
      password: 'bmstubmstu123',
      db: 'iu9mobile',
      characterSet: CharacterSet.UTF8MB4,
    ),
  );
  try {
    return await action(connection);
  } finally {
    await connection.close();
  }
}

Future<void> createTable() => _query((connection) async {
  await connection.query('''CREATE TABLE IF NOT EXISTS Trofimenko (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    surname VARCHAR(100) NOT NULL,
    mail VARCHAR(255) CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL UNIQUE,
    ifsend TINYINT(1) NOT NULL DEFAULT 0
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4''');
  await connection.query(
    '''INSERT INTO Trofimenko (name,surname,mail,ifsend)
    VALUES (?,?,?,0) ON DUPLICATE KEY UPDATE mail=mail''',
    ['Данила', 'Посевин', 'posevin@bmstu.ru'],
  );
});

Future<List<Map<String, dynamic>>> getSubscribers() => _query((connection) async {
  final rows = await connection.query('SELECT * FROM Trofimenko ORDER BY id');
  return rows.map((row) => row.toColumnMap()).toList();
});

Future<void> addSubscriber(String name, String surname, String email) =>
    _query((connection) async {
      await connection.query(
        'INSERT INTO Trofimenko (name,surname,mail) VALUES (?,?,?)',
        [name, surname, email],
      );
    });

Future<void> markSent(int id) => _query((connection) async {
  await connection.query('UPDATE Trofimenko SET ifsend=1 WHERE id=?', [id]);
});
