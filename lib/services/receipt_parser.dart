import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/receipt.dart';

class ReceiptParser {
  ReceiptParser({this.endpoint = const String.fromEnvironment('PARSER_URL')});
  final String endpoint;

  bool get isConfigured => endpoint.trim().isNotEmpty;

  Future<Receipt> parse(File image) async {
    if (!isConfigured) {
      throw StateError('Live bill reading is not connected yet.');
    }
    final request = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..files.add(await http.MultipartFile.fromPath('receipt', image.path));
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Bill reading failed (${response.statusCode}).');
    }
    return Receipt.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }
}
