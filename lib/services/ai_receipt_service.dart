import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';

class AiReceiptException implements Exception {
  const AiReceiptException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class ShelfPriceResult {
  const ShelfPriceResult({
    required this.productName,
    required this.confidence,
    this.mrp,
    this.salePrice,
    this.packSize,
    this.warnings = const [],
  });

  final String productName;
  final double? mrp;
  final double? salePrice;
  final String? packSize;
  final double confidence;
  final List<String> warnings;

  factory ShelfPriceResult.fromJson(Map<String, dynamic> json) =>
      ShelfPriceResult(
        productName: json['productName']?.toString() ?? '',
        mrp: (json['mrp'] as num?)?.toDouble(),
        salePrice: (json['salePrice'] as num?)?.toDouble(),
        packSize: json['packSize']?.toString(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? .5,
        warnings: (json['warnings'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .where((value) => value.trim().isNotEmpty)
            .toList(),
      );
}

class AiReceiptService {
  AiReceiptService({http.Client? client, String? endpoint})
      : client = client ?? http.Client(),
        endpoint =
            endpoint ?? const String.fromEnvironment('CARTSENSE_AI_ENDPOINT');

  static const _deviceIdKey = 'cartsense_ai_device_id';
  static const _safeUploadBytes = 12 * 1024 * 1024;

  final http.Client client;
  final String endpoint;

  bool get isConfigured => endpoint.trim().isNotEmpty;

  Future<Receipt> parse(File image) async {
    return parseImages([image]);
  }

  Future<Receipt> parseImages(List<File> images) async {
    if (!isConfigured) {
      throw const AiReceiptException(
        'AI Enhanced Scan is not configured in this build. Use private scanning for now.',
        code: 'AI_NOT_CONFIGURED',
      );
    }
    if (images.isEmpty) {
      throw const AiReceiptException(
        'Add at least one receipt photo to scan.',
        code: 'IMAGE_REQUIRED',
      );
    }
    if (images.length > 4) {
      throw const AiReceiptException(
        'Use up to 4 photos for one long receipt.',
        code: 'TOO_MANY_IMAGES',
      );
    }

    final uploadImages = <File>[];
    for (final image in images) {
      uploadImages.add(await _prepareUpload(image));
    }
    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.headers.addAll({
      'x-cartsense-device': await _deviceId(),
      'x-cartsense-client': 'android/0.9.0',
      'x-cartsense-receipt-parts': uploadImages.length.toString(),
    });
    for (var index = 0; index < uploadImages.length; index += 1) {
      final uploadImage = uploadImages[index];
      request.files.add(await http.MultipartFile.fromPath(
        'receipt',
        uploadImage.path,
        filename: 'receipt_part_${index + 1}${_extensionFor(uploadImage.path)}',
        contentType: _mediaTypeFor(uploadImage.path),
      ));
    }

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
    receipt.imagePath = images.first.path;
    if (receipt.items.isEmpty || receipt.printedTotal <= 0) {
      throw const AiReceiptException(
        'The AI found text but could not confirm the products and total. Retake a clearer photo.',
        code: 'AI_RESULT_INCOMPLETE',
      );
    }
    return receipt;
  }

  Future<ShelfPriceResult> parseShelfPrice(File image) async {
    if (!isConfigured) {
      throw const AiReceiptException(
        'AI shelf price capture is not configured in this build.',
        code: 'AI_NOT_CONFIGURED',
      );
    }
    final uploadImage = await _prepareUpload(image);
    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.headers.addAll({
      'x-cartsense-device': await _deviceId(),
      'x-cartsense-client': 'android/0.9.0',
    });
    request.fields['mode'] = 'shelf_price';
    request.files.add(await http.MultipartFile.fromPath(
      'price',
      uploadImage.path,
      filename: 'shelf_price${_extensionFor(uploadImage.path)}',
      contentType: _mediaTypeFor(uploadImage.path),
    ));

    late http.StreamedResponse streamed;
    try {
      streamed =
          await client.send(request).timeout(const Duration(seconds: 90));
    } on SocketException {
      throw const AiReceiptException(
        'No internet connection. Type the shelf price manually for now.',
        code: 'OFFLINE',
      );
    } on TimeoutException {
      throw const AiReceiptException(
        'The shelf price reader took too long. Try again or type the price.',
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
        'The AI service returned an unreadable shelf-price response.',
        code: 'AI_RESPONSE_INVALID',
      );
    }
    if (streamed.statusCode != 200) {
      throw AiReceiptException(
        payload['error']?.toString() ??
            'The AI reader could not read this shelf label.',
        code: payload['code']?.toString(),
      );
    }
    final shelfJson = payload['shelfPrice'];
    if (shelfJson is! Map) {
      throw const AiReceiptException(
        'The shelf label result was incomplete. Retake the photo closer to the label.',
        code: 'AI_RESULT_INVALID',
      );
    }
    final result = ShelfPriceResult.fromJson(
      Map<String, dynamic>.from(shelfJson),
    );
    if (result.productName.trim().isEmpty &&
        result.mrp == null &&
        result.salePrice == null) {
      throw const AiReceiptException(
        'Could not read a product name or price from this shelf label.',
        code: 'AI_RESULT_INCOMPLETE',
      );
    }
    return result;
  }

  Future<File> _prepareUpload(File image) async {
    if (await image.length() <= _safeUploadBytes) {
      return image;
    }

    throw const AiReceiptException(
      'This photo is too large to scan. Crop it to the receipt or retake it closer to the bill.',
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
