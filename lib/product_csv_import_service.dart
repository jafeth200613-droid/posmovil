import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'database_helper.dart';

class ProductCsvImportService {
  ProductCsvImportService._();

  static const int _maxBatchSize = 500;
  static const List<String> _headers = [
    'Código de Barras',
    'Nombre',
    'Categoría',
    'Precio',
    'Stock Inicial',
  ];

  static Future<int?> importProducts() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result.isEmpty) return null;

    final file = result.single;
    final bytes = await file.readAsBytes();
    final content = utf8
        .decode(bytes, allowMalformed: false)
        .replaceFirst('\uFEFF', '');
    final delimiter = _detectDelimiter(content);
    final rows = Csv(
      fieldDelimiter: delimiter,
      autoDetect: false,
    ).decode(content);
    final products = _parseRows(rows);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión antes de importar productos.');
    }

    final db = FirebaseFirestore.instance;
    final references = products
        .map(
          (product) =>
              _productReference(db, user.uid, product['code'] as String),
        )
        .toList();
    final codes = products.map((product) => product['code'] as String).toList();
    for (var start = 0; start < codes.length; start += 30) {
      final end = (start + 30).clamp(0, codes.length);
      final existing = await db
          .collection('products')
          .where('uid', isEqualTo: user.uid)
          .where('code', whereIn: codes.sublist(start, end))
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        final code = existing.docs.first.data()['code'];
        throw StateError('El código "$code" ya existe en Firestore.');
      }
    }

    final localProducts = await DatabaseHelper.instance.getProducts();
    final localCodes = localProducts
        .map((product) => product['code']?.toString())
        .whereType<String>()
        .toSet();
    for (final product in products) {
      final code = product['code'] as String;
      if (localCodes.contains(code)) {
        throw StateError('El código "$code" ya existe en el inventario.');
      }
    }

    final batch = db.batch();
    for (var index = 0; index < products.length; index++) {
      batch.set(references[index], {
        ...products[index],
        'uid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await DatabaseHelper.instance.insertProducts(products);

    return products.length;
  }

  static DocumentReference<Map<String, dynamic>> _productReference(
    FirebaseFirestore firestore,
    String uid,
    String code,
  ) {
    final encodedCode = base64Url.encode(utf8.encode(code)).replaceAll('=', '');
    return firestore.collection('products').doc('$uid-$encodedCode');
  }

  static List<Map<String, dynamic>> _parseRows(List<List<dynamic>> rows) {
    final nonEmptyRows = rows
        .where((row) => row.any((cell) => cell.toString().trim().isNotEmpty))
        .toList();
    if (nonEmptyRows.isEmpty) {
      throw const FormatException('El CSV no contiene productos.');
    }

    final firstRow = nonEmptyRows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    final hasHeader =
        firstRow.length == _headers.length &&
        List.generate(_headers.length, (index) {
          return firstRow[index] == _headers[index].toLowerCase();
        }).every((matches) => matches);
    final dataRows = hasHeader ? nonEmptyRows.skip(1).toList() : nonEmptyRows;
    if (dataRows.isEmpty) {
      throw const FormatException('El CSV no contiene filas de productos.');
    }
    if (dataRows.length > _maxBatchSize) {
      throw const FormatException(
        'El archivo supera el límite de 500 productos por importación.',
      );
    }

    final products = <Map<String, dynamic>>[];
    final codes = <String>{};
    for (var index = 0; index < dataRows.length; index++) {
      final rowNumber = index + (hasHeader ? 2 : 1);
      final row = dataRows[index];
      if (row.length != _headers.length) {
        throw FormatException(
          'La fila $rowNumber debe tener exactamente 5 columnas.',
        );
      }

      final code = row[0].toString().trim();
      final name = row[1].toString().trim();
      final category = row[2].toString().trim();
      final priceText = row[3].toString().trim();
      final stockText = row[4].toString().trim();
      if (code.isEmpty ||
          name.isEmpty ||
          priceText.isEmpty ||
          stockText.isEmpty) {
        throw FormatException(
          'La fila $rowNumber tiene campos obligatorios vacíos.',
        );
      }
      if (!codes.add(code)) {
        throw FormatException(
          'El código "$code" está repetido en la fila $rowNumber.',
        );
      }

      final price = _parsePrice(priceText, rowNumber);
      final stock = int.tryParse(stockText);
      if (stock == null || stock < 0) {
        throw FormatException(
          'El stock de la fila $rowNumber debe ser un entero no negativo.',
        );
      }
      products.add({
        'code': code,
        'name': name,
        'category': category.isEmpty ? 'General' : category,
        'price': price,
        'stock': stock,
      });
    }
    return products;
  }

  static double _parsePrice(String value, int rowNumber) {
    var normalized = value.replaceAll('₡', '').replaceAll(' ', '');
    if (normalized.contains(',') && normalized.contains('.')) {
      if (normalized.lastIndexOf(',') > normalized.lastIndexOf('.')) {
        normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = normalized.replaceAll(',', '');
      }
    } else if (normalized.contains(',')) {
      normalized = normalized.replaceAll(',', '.');
    }

    final price = double.tryParse(normalized);
    if (price == null || !price.isFinite || price < 0) {
      throw FormatException(
        'El precio de la fila $rowNumber no es un número válido.',
      );
    }
    return price;
  }

  static String _detectDelimiter(String content) {
    final firstLine = content
        .replaceFirst('\uFEFF', '')
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    var commas = 0;
    var semicolons = 0;
    var insideQuotes = false;
    for (var index = 0; index < firstLine.length; index++) {
      final character = firstLine[index];
      if (character == '"') {
        if (insideQuotes &&
            index + 1 < firstLine.length &&
            firstLine[index + 1] == '"') {
          index++;
        } else {
          insideQuotes = !insideQuotes;
        }
      } else if (!insideQuotes) {
        if (character == ',') commas++;
        if (character == ';') semicolons++;
      }
    }
    return semicolons > commas ? ';' : ',';
  }
}
