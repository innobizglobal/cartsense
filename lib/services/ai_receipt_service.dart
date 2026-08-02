import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';

class AiReceiptException implements Exception {
  const AiReceiptException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class AiReceiptService {
  AiReceiptService({http.Client? client, String? endpoint})
      : client = client ?? http.Client(),
        endpoint =
            endpoint ?? const String.fromEnvironment('CARTSENSE_AI_ENDPOINT');

  static const _deviceIdKey = 'cartsense_ai_device_id';
  static const _safeUploadBytes = 900 * 1024;

  final http.Client client;
  final String endpoint;

  bool get isConfigured => endpoint.trim().isNotEmpty;

  Future<Receipt> parse(File image) async {
    if (!isConfigured) {
      throw const AiReceiptException(
        'AI Enhanced Scan is not configured in this build. Use private scanning for now.',
        code: 'AI_NOT_CONFIGURED',
      );
    }

    final uploadImage = await _prepareUpload(image);
    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.headers.addAll({
      'x-cartsense-device': await _deviceId(),
      'x-cartsense-client': 'android/0.6.0',
    });
    request.files.add(await http.MultipartFile.fromPath(
      'receipt',
      uploadImage.path,
      filename: 'receipt${_extensionFor(uploadImage.path)}',
      contentType: _mediaTypeFor(uploadImage.path),
    ));

    late http.StreamedResponse streamed;
    try {
      streamed =
          await client.send(request).timeout(const Duration(seconds: 160));
    } on SocketException {
      throw const AiReceiptException(
        'No internet connection. You can still use the private on-device reader.',
        code: 'OFFLINE',
      );
    } on HttpException {
      throw const AiReceiptException(
        'The secure AI service could not be reached. Try again shortly.',
        code: 'AI_UNREACHABLE',
      );
    } on TimeoutException {
      throw const AiReceiptException(
        'The AI reader took too long. Try again or use private scanning.',
        code: 'AI_TIMEOUT',
      );
    } on FormatException {
      throw const AiReceiptException(
        'The AI service address in this build is invalid.',
        code: 'AI_ENDPOINT_INVALID',
      );
    }

    final body = await streamed.stream.bytesToString();
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      throw const AiReceiptException(
        'The AI service returned an unreadable response. Try again shortly.',
        code: 'AI_RESPONSE_INVALID',
      );
    }

    if (streamed.statusCode != 200) {
      throw AiReceiptException(
        payload['error']?.toString() ??
            'The AI reader could not process this receipt.',
        code: payload['code']?.toString(),
      );
    }

    final receiptJson = payload['receipt'];
    if (receiptJson is! Map) {
      throw const AiReceiptException(
        'The AI result was incomplete. Retake the photo with the whole receipt visible.',
        code: 'AI_RESULT_INVALID',
      );
    }
    final receipt = Receipt.fromJson(Map<String, dynamic>.from(receiptJson));
    receipt.imagePath = image.path;
    if (receipt.items.isEmpty || receipt.printedTotal <= 0) {
      throw const AiReceiptException(
        'The AI found text but could not confirm the products and total. Retake a clearer photo.',
        code: 'AI_RESULT_INCOMPLETE',
      );
    }
    return receipt;
  }

  Future<File> _prepareUpload(File image) async {
    if (await image.length() <= _safeUploadBytes &&
        !image.path.toLowerCase().endsWith('.png')) {
      return image;
    }

    final directory = await getTemporaryDirectory();
    File? best;
    for (final quality in const [82, 68, 54, 42]) {
      final target =
          '${directory.path}${Platform.pathSeparator}cartsense-ai-${DateTime.now().microsecondsSinceEpoch}-$quality.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        image.absolute.path,
        target,
        minWidth: 1600,
        minHeight: 1600,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed == null) continue;
      best = File(compressed.path);
      if (await best.length() <= _safeUploadBytes) return best;
    }

    if (best != null && await best.length() <= _safeUploadBytes) return best;
    throw const AiReceiptException(
      'This photo is too large to scan. Crop it to the receipt and try again.',
      code: 'IMAGE_TOO_LARGE',
    );
  }

  Future<String> _deviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    final encoded = base64Url.encode(utf8.encode(random)).replaceAll('=', '');
    await preferences.setString(_deviceIdKey, encoded);
    return encoded;
  }

  String _extensionFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  MediaType _mediaTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }
}
