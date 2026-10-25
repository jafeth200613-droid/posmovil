import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_inventory.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        name TEXT,
        price REAL,
        stock INTEGER,
        category TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_name TEXT,
        price REAL,
        date TEXT,
        fiado_item_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE fiados (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_name TEXT,
        amount REAL,
        date TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await _createFiadoItemsTable(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      await _ensureFiadosSchema(db);
    }
    if (oldVersion < 5) {
      await _ensureFiadosSchema(db);
      await _ensureFiadoTrackingSchema(db);
    }
  }

  Future<void> _createFiadoItemsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fiado_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fiado_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
  }

  Future<void> _ensureFiadoTrackingSchema(DatabaseExecutor db) async {
    await _createFiadoItemsTable(db);

    final fiadoColumns = await _getFiadoColumnInfo(db);
    if (!fiadoColumns.any((column) => column['name'] == 'status')) {
      await db.execute(
        "ALTER TABLE fiados ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
      );
    }

    final salesColumns = await db.rawQuery('PRAGMA table_info(sales)');
    if (!salesColumns.any((column) => column['name'] == 'fiado_item_id')) {
      await db.execute('ALTER TABLE sales ADD COLUMN fiado_item_id INTEGER');
    }
  }

  Future<void> _createFiadosTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fiados (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_name TEXT,
        amount REAL,
        date TEXT
      )
    ''');
  }

  Future<void> _ensureFiadosSchema(DatabaseExecutor db) async {
    await _createFiadosTable(db);

    Future<Set<String>> getColumns() async {
      final columns = await db.rawQuery('PRAGMA table_info(fiados)');
      return columns.map((column) => column['name'] as String).toSet();
    }

    var columns = await getColumns();
    const definitions = {
      'client_name': "TEXT NOT NULL DEFAULT ''",
      'amount': 'REAL NOT NULL DEFAULT 0',
      'date': "TEXT NOT NULL DEFAULT ''",
    };

    for (final entry in definitions.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE fiados ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }

    columns = await getColumns();

    const legacyColumns = {
      'client_name': [
        'customer_name',
        'nombre_cliente',
        'cliente',
        'nombre',
        'client',
      ],
      'amount': ['monto_deuda', 'monto', 'deuda', 'total'],
      'date': ['fecha', 'created_at'],
    };

    for (final entry in legacyColumns.entries) {
      final legacyColumn = entry.value.cast<String?>().firstWhere(
        (column) => column != null && columns.contains(column),
        orElse: () => null,
      );
      if (legacyColumn != null) {
        await db.execute(
          'UPDATE fiados SET ${entry.key} = "$legacyColumn" '
          'WHERE ${entry.key} IS NULL OR ${entry.key} = '
          '${entry.key == 'client_name' || entry.key == 'date' ? "''" : '0'}',
        );
      }
    }
  }

  // --- PRODUCTOS ---
  Future<int> insertProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('products', row);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await instance.database;
    return await db.query('products', orderBy: 'name ASC');
  }

  Future<int> updateProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    int id = row['id'];
    return await db.update('products', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateProductStock(int id, int newStock) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // --- VENTAS ---
  Future<int> insertSale(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('sales', row);
  }

  Future<List<Map<String, dynamic>>> getSales() async {
    final db = await instance.database;
    return await db.query('sales', orderBy: 'id DESC');
  }

  Future<int> deleteSale(int id) async {
    final db = await instance.database;
    return await db.delete('sales', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllSales() async {
    final db = await instance.database;
    return await db.delete('sales');
  }

  // --- FIADOS ---
  Future<int> insertFiado({
    required String clientName,
    required double amount,
    required String date,
    String? description,
    List<Map<String, dynamic>> items = const [],
  }) async {
    final normalizedName = clientName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('El nombre del cliente es obligatorio.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('El monto debe ser mayor que cero.');
    }

    final db = await instance.database;
    return db.transaction((txn) async {
      final columnInfo = await _getFiadoColumnInfo(txn);
      final id = await txn.insert(
        'fiados',
        _fiadoValues(
          columnInfo,
          normalizedName,
          amount,
          date,
          description ?? 'Cuenta por cobrar de $normalizedName',
        ),
      );
      await _insertFiadoItems(txn, id, items, balance: amount);
      return id;
    });
  }

  Future<int> insertFiadoFromCart({
    required String clientName,
    required double amount,
    required String date,
    required List<Map<String, dynamic>> items,
    String? description,
  }) async {
    final normalizedName = clientName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('El nombre del cliente es obligatorio.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('El monto debe ser mayor que cero.');
    }
    if (items.isEmpty) {
      throw ArgumentError('El carrito está vacío.');
    }

    final db = await instance.database;
    return db.transaction((txn) async {
      final fiadoColumnInfo = await _getFiadoColumnInfo(txn);
      for (final item in items) {
        final products = await txn.query(
          'products',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [item['id']],
          limit: 1,
        );
        if (products.isEmpty) {
          throw StateError('No se encontró el producto ${item['name']}.');
        }

        final rawStock = products.first['stock'];
        final stock = rawStock is num ? rawStock.toInt() : 0;
        final quantity = (item['quantity'] as num).toInt();
        if (quantity <= 0 || quantity > stock) {
          throw StateError('Stock insuficiente para ${item['name']}.');
        }

        await txn.update(
          'products',
          {'stock': stock - quantity},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }

      final fiadoId = await txn.insert(
        'fiados',
        _fiadoValues(
          fiadoColumnInfo,
          normalizedName,
          amount,
          date,
          description ??
              items
                  .map((item) => '${item['name']} x${item['quantity']}')
                  .join(', '),
        ),
      );
      await _insertFiadoItems(txn, fiadoId, items, balance: amount);
      return fiadoId;
    });
  }

  Future<void> _insertFiadoItems(
    DatabaseExecutor db,
    int fiadoId,
    List<Map<String, dynamic>> items, {
    required double balance,
  }) async {
    var assignedAmount = 0.0;
    for (final item in items) {
      final quantity = (item['quantity'] as num).toInt();
      final unitPrice = (item['price'] as num).toDouble();
      if (quantity <= 0 || !unitPrice.isFinite || unitPrice < 0) {
        throw ArgumentError('Hay un producto con cantidad o precio inválido.');
      }
      assignedAmount += unitPrice * quantity;
      await db.insert('fiado_items', {
        'fiado_id': fiadoId,
        'product_id': item['id'],
        'product_name': item['name'].toString(),
        'unit_price': unitPrice,
        'quantity': quantity,
      });
    }

    if (assignedAmount > balance + 0.005) {
      throw ArgumentError(
        'El total de productos supera el monto de la cuenta.',
      );
    }

    final remaining = balance - assignedAmount;
    if (remaining > 0.005) {
      await db.insert('fiado_items', {
        'fiado_id': fiadoId,
        'product_name': 'Saldo pendiente',
        'unit_price': remaining,
        'quantity': 1,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getFiadoItems(int fiadoId) async {
    final db = await instance.database;
    return db.query(
      'fiado_items',
      where: 'fiado_id = ?',
      whereArgs: [fiadoId],
      orderBy: 'id ASC',
    );
  }

  Future<void> addFiadoItem({
    required int fiadoId,
    required int productId,
    required String productName,
    required double unitPrice,
    required int quantity,
  }) async {
    if (quantity <= 0 || !unitPrice.isFinite || unitPrice < 0) {
      throw ArgumentError('Cantidad o precio inválido.');
    }

    final db = await instance.database;
    await db.transaction((txn) async {
      final fiadoRows = await txn.query(
        'fiados',
        where: 'id = ?',
        whereArgs: [fiadoId],
        limit: 1,
      );
      if (fiadoRows.isEmpty) {
        throw StateError('No se encontró la cuenta fiada.');
      }
      final fiado = fiadoRows.first;
      if (fiado['status'] == 'paid') {
        throw StateError('Reanuda la cuenta antes de agregar productos.');
      }

      await txn.insert('fiado_items', {
        'fiado_id': fiadoId,
        'product_id': productId,
        'product_name': productName,
        'unit_price': unitPrice,
        'quantity': quantity,
      });
      await txn.update(
        'fiados',
        {'amount': (fiado['amount'] as num).toDouble() + unitPrice * quantity},
        where: 'id = ?',
        whereArgs: [fiadoId],
      );
    });
  }

  Future<int> updateFiadoName(int fiadoId, String clientName) async {
    final normalizedName = clientName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('El nombre del cliente es obligatorio.');
    }
    final db = await instance.database;
    final columns = await _getFiadoColumnInfo(db);
    final available = columns.map((column) => column['name'] as String).toSet();
    final values = <String, Object>{};
    for (final name in [
      'client_name',
      'customer_name',
      'nombre_cliente',
      'cliente',
      'nombre',
      'client',
    ]) {
      if (available.contains(name)) values[name] = normalizedName;
    }
    return db.update('fiados', values, where: 'id = ?', whereArgs: [fiadoId]);
  }

  Future<void> setFiadoItemPaid(int itemId, {required bool paid}) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'fiado_items',
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('No se encontró el producto fiado.');

      final item = rows.first;
      final isPaid = item['status'] == 'paid';
      if (isPaid == paid) return;

      final fiadoRows = await txn.query(
        'fiados',
        where: 'id = ?',
        whereArgs: [item['fiado_id']],
        limit: 1,
      );
      if (fiadoRows.isEmpty) {
        throw StateError('No se encontró la cuenta fiada.');
      }
      final fiado = fiadoRows.first;
      final amount = (fiado['amount'] as num).toDouble();
      final lineTotal =
          (item['unit_price'] as num).toDouble() *
          (item['quantity'] as num).toInt();

      if (paid) {
        await _recordFiadoItemSales(txn, itemId, item);
        await txn.update(
          'fiados',
          {'amount': (amount - lineTotal).clamp(0, double.infinity)},
          where: 'id = ?',
          whereArgs: [item['fiado_id']],
        );
      } else {
        await txn.delete(
          'sales',
          where: 'fiado_item_id = ?',
          whereArgs: [itemId],
        );
        await txn.update(
          'fiados',
          {'amount': amount + lineTotal},
          where: 'id = ?',
          whereArgs: [item['fiado_id']],
        );
      }

      await txn.update(
        'fiado_items',
        {'status': paid ? 'paid' : 'pending'},
        where: 'id = ?',
        whereArgs: [itemId],
      );
      await _refreshFiadoStatus(txn, item['fiado_id'] as int);
    });
  }

  Future<void> setFiadoPaid(int fiadoId, {required bool paid}) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final fiadoRows = await txn.query(
        'fiados',
        where: 'id = ?',
        whereArgs: [fiadoId],
        limit: 1,
      );
      if (fiadoRows.isEmpty) {
        throw StateError('No se encontró la cuenta fiada.');
      }
      final fiado = fiadoRows.first;
      final items = await txn.query(
        'fiado_items',
        where: 'fiado_id = ?',
        whereArgs: [fiadoId],
        orderBy: 'id ASC',
      );

      if (paid && items.isEmpty) {
        final amount = (fiado['amount'] as num).toDouble();
        if (amount > 0) {
          await txn.insert('fiado_items', {
            'fiado_id': fiadoId,
            'product_name': 'Saldo pendiente',
            'unit_price': amount,
            'quantity': 1,
          });
        }
      }

      final itemIds = items.map((item) => item['id'] as int).toList();
      if (paid && itemIds.isEmpty) {
        final created = await txn.query(
          'fiado_items',
          columns: ['id'],
          where: 'fiado_id = ?',
          whereArgs: [fiadoId],
          orderBy: 'id DESC',
          limit: 1,
        );
        itemIds.addAll(created.map((item) => item['id'] as int));
      }

      for (final itemId in itemIds) {
        await _setFiadoItemPaidInTransaction(txn, itemId, paid: paid);
      }
      await _refreshFiadoStatus(txn, fiadoId);
    });
  }

  Future<void> _setFiadoItemPaidInTransaction(
    Transaction txn,
    int itemId, {
    required bool paid,
  }) async {
    final rows = await txn.query(
      'fiado_items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final item = rows.first;
    final isPaid = item['status'] == 'paid';
    if (isPaid == paid) return;

    final fiadoRows = await txn.query(
      'fiados',
      where: 'id = ?',
      whereArgs: [item['fiado_id']],
      limit: 1,
    );
    if (fiadoRows.isEmpty) throw StateError('No se encontró la cuenta fiada.');
    final fiado = fiadoRows.first;
    final amount = (fiado['amount'] as num).toDouble();
    final lineTotal =
        (item['unit_price'] as num).toDouble() *
        (item['quantity'] as num).toInt();

    if (paid) {
      await _recordFiadoItemSales(txn, itemId, item);
      await txn.update(
        'fiados',
        {'amount': (amount - lineTotal).clamp(0, double.infinity)},
        where: 'id = ?',
        whereArgs: [item['fiado_id']],
      );
    } else {
      await txn.delete(
        'sales',
        where: 'fiado_item_id = ?',
        whereArgs: [itemId],
      );
      await txn.update(
        'fiados',
        {'amount': amount + lineTotal},
        where: 'id = ?',
        whereArgs: [item['fiado_id']],
      );
    }
    await txn.update(
      'fiado_items',
      {'status': paid ? 'paid' : 'pending'},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> _recordFiadoItemSales(
    Transaction txn,
    int itemId,
    Map<String, Object?> item,
  ) async {
    final quantity = (item['quantity'] as num).toInt();
    final price = (item['unit_price'] as num).toDouble();
    final saleDate = DateTime.now().toString().substring(0, 16);
    for (var i = 0; i < quantity; i++) {
      await txn.insert('sales', {
        'product_name': item['product_name'],
        'price': price,
        'date': saleDate,
        'fiado_item_id': itemId,
      });
    }
  }

  Future<void> _refreshFiadoStatus(Transaction txn, int fiadoId) async {
    final items = await txn.query(
      'fiado_items',
      columns: ['status'],
      where: 'fiado_id = ?',
      whereArgs: [fiadoId],
    );
    final allPaid =
        items.isNotEmpty && items.every((item) => item['status'] == 'paid');
    await txn.update(
      'fiados',
      {'status': allPaid ? 'paid' : 'pending'},
      where: 'id = ?',
      whereArgs: [fiadoId],
    );
  }

  Future<List<Map<String, Object?>>> _getFiadoColumnInfo(
    DatabaseExecutor db,
  ) async {
    return db.rawQuery('PRAGMA table_info(fiados)');
  }

  Map<String, Object> _fiadoValues(
    List<Map<String, Object?>> columnInfo,
    String clientName,
    double amount,
    String date,
    String description,
  ) {
    final values = <String, Object>{};
    final columns = columnInfo
        .map((column) => column['name'] as String)
        .toSet();

    for (final nameColumn in [
      'client_name',
      'customer_name',
      'nombre_cliente',
      'cliente',
      'nombre',
      'client',
    ]) {
      if (columns.contains(nameColumn)) {
        values[nameColumn] = clientName;
      }
    }

    for (final descriptionColumn in [
      'description',
      'descriptions',
      'detail',
      'details',
      'concept',
      'concepto',
      'items',
      'products',
    ]) {
      if (columns.contains(descriptionColumn)) {
        values[descriptionColumn] = description;
      }
    }

    for (final amountColumn in [
      'amount',
      'monto_deuda',
      'monto',
      'deuda',
      'total',
    ]) {
      if (columns.contains(amountColumn)) {
        values[amountColumn] = amount;
      }
    }

    for (final dateColumn in ['date', 'fecha', 'created_at']) {
      if (columns.contains(dateColumn)) {
        values[dateColumn] = date;
      }
    }

    for (final column in columnInfo) {
      final name = column['name'] as String;
      final isRequired = column['notnull'] == 1;
      final hasDefault = column['dflt_value'] != null;
      final isPrimaryKey = column['pk'] == 1;
      if (!isRequired ||
          hasDefault ||
          isPrimaryKey ||
          values.containsKey(name)) {
        continue;
      }

      final type = (column['type'] as String? ?? '').toUpperCase();
      values[name] =
          type.contains('INT') ||
              type.contains('REAL') ||
              type.contains('NUM') ||
              type.contains('DEC')
          ? 0
          : '';
    }
    return values;
  }

  Future<List<Map<String, dynamic>>> getFiados() async {
    final db = await instance.database;
    final rows = await db.query('fiados', orderBy: 'id DESC');
    return rows.map((row) {
      final normalizedRow = Map<String, dynamic>.from(row);
      final name =
          [
            row['client_name'],
            row['customer_name'],
            row['nombre_cliente'],
            row['cliente'],
            row['nombre'],
            row['client'],
          ].whereType<String>().firstWhere(
            (value) => value.trim().isNotEmpty,
            orElse: () => '',
          );
      final amountValues = [
        row['amount'],
        row['monto_deuda'],
        row['monto'],
        row['deuda'],
        row['total'],
      ].whereType<num>().toList();
      final amount = amountValues.firstWhere(
        (value) => value != 0,
        orElse: () => amountValues.isEmpty ? 0 : amountValues.first,
      );
      final date = [row['date'], row['fecha'], row['created_at']]
          .whereType<String>()
          .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
      normalizedRow['client_name'] = name;
      normalizedRow['amount'] = amount;
      normalizedRow['date'] = date;
      return normalizedRow;
    }).toList();
  }

  Future<int> updateFiado(Map<String, dynamic> row) async {
    final db = await instance.database;
    int id = row['id'];
    final columnInfo = await _getFiadoColumnInfo(db);
    final clientName = (row['client_name'] ?? row['customer_name'] ?? '')
        .toString();
    final amount = (row['amount'] as num).toDouble();
    final date = (row['date'] ?? '').toString();
    final values = _fiadoValues(
      columnInfo,
      clientName,
      amount,
      date,
      (row['description'] ?? 'Cuenta por cobrar de $clientName').toString(),
    );
    return db.update('fiados', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteFiado(int id) async {
    final db = await instance.database;
    return db.transaction((txn) async {
      await txn.delete('fiado_items', where: 'fiado_id = ?', whereArgs: [id]);
      return txn.delete('fiados', where: 'id = ?', whereArgs: [id]);
    });
  }
}
