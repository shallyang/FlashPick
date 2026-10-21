import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// 待办模型。
class Todo {
  Todo({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.done = false,
    this.doneAt,
    this.source = 'hotkey',
    this.mirrorId,
  });

  final String id;
  String text;
  final int createdAt;
  int updatedAt;
  bool done;
  int? doneAt;
  String source; // hotkey | panel | menu
  String? mirrorId; // EventKit calendarItemExternalIdentifier

  Map<String, Object?> toRow() => {
        'id': id,
        'text': text,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'done': done ? 1 : 0,
        'done_at': doneAt,
        'source': source,
        'mirror_id': mirrorId,
      };

  static Todo fromRow(Map<String, Object?> row) => Todo(
        id: row['id'] as String,
        text: row['text'] as String,
        createdAt: row['created_at'] as int,
        updatedAt: row['updated_at'] as int,
        done: (row['done'] as int) == 1,
        doneAt: row['done_at'] as int?,
        source: (row['source'] as String?) ?? 'hotkey',
        mirrorId: row['mirror_id'] as String?,
      );
}

/// 本地存储：SQLite（不登录时唯一数据源，为未来云同步预留字段）。
class Store {
  Store._();
  static final Store instance = Store._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'flashpick.db');
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE todos(
              id TEXT PRIMARY KEY,
              text TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              done INTEGER NOT NULL DEFAULT 0,
              done_at INTEGER,
              source TEXT NOT NULL DEFAULT 'hotkey',
              mirror_id TEXT,
              deleted INTEGER NOT NULL DEFAULT 0,
              remote_updated_at INTEGER
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_todos_updated ON todos(updated_at DESC)');
          await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
        },
      ),
    );
    return _db!;
  }

  // ---- settings ----

  Future<String?> getSetting(String key) async {
    final d = await db;
    final rows = await d.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- todos ----

  Future<List<Todo>> listTodos({String? keyword, int limit = 500}) async {
    final d = await db;
    final where = keyword == null || keyword.isEmpty ? null : 'text LIKE ? AND deleted = 0';
    final args = keyword == null || keyword.isEmpty
        ? <Object>[]
        : ['%$keyword%'];
    final rows = await d.query('todos',
        where: where, whereArgs: args.isEmpty ? null : args,
        orderBy: 'created_at DESC', limit: limit);
    return rows.map(Todo.fromRow).toList();
  }

  Future<Todo> insertTodo(Todo todo) async {
    final d = await db;
    await d.insert('todos', todo.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return todo;
  }

  Future<void> setDone(String id, bool done) async {
    final d = await db;
    await d.update(
        'todos',
        {
          'done': done ? 1 : 0,
          'done_at': done ? DateTime.now().millisecondsSinceEpoch : null,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> remove(String id) async {
    final d = await db;
    // 软删除，为云同步预留
    await d.update('todos', {'deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setMirrorId(String id, String? mirrorId) async {
    final d = await db;
    await d.update('todos', {'mirror_id': mirrorId}, where: 'id = ?', whereArgs: [id]);
  }

  Future<String> dbPath() async => p.join((await getApplicationSupportDirectory()).path, 'flashpick.db');
}

const _uuid = Uuid();

String newId() => _uuid.v4();
