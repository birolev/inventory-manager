import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _maxImageBytes = 10 * 1024 * 1024;
const _maxCacheBytes = 250 * 1024 * 1024;

Future<ImageProvider> imageProviderFor(
  String url, {
  int? cacheWidth,
  String? fallbackUrl,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
    return fallbackUrl == null
        ? _networkProvider(url, cacheWidth)
        : imageProviderFor(fallbackUrl, cacheWidth: cacheWidth);
  }
  try {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}${Platform.pathSeparator}item-photo-cache');
    await directory.create(recursive: true);
    final key = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    final file = File('${directory.path}${Platform.pathSeparator}$key.img');
    if (!await file.exists()) {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          !contentType.startsWith('image/') || response.bodyBytes.isEmpty ||
          response.bodyBytes.length > _maxImageBytes) {
        return fallbackUrl == null
            ? _networkProvider(url, cacheWidth)
            : await imageProviderFor(fallbackUrl, cacheWidth: cacheWidth);
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(file.path);
      await _trimCache(directory, file);
    }
    final provider = FileImage(file);
    return cacheWidth == null ? provider : ResizeImage(provider, width: cacheWidth);
  } catch (_) {
    return fallbackUrl == null
        ? _networkProvider(url, cacheWidth)
        : await imageProviderFor(fallbackUrl, cacheWidth: cacheWidth);
  }
}

ImageProvider _networkProvider(String url, int? cacheWidth) => cacheWidth == null
    ? NetworkImage(url)
    : ResizeImage(NetworkImage(url), width: cacheWidth);

Future<void> _trimCache(Directory directory, File newest) async {
  try {
    final files = <({File file, int bytes, DateTime modified})>[];
    var total = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || entity.path.endsWith('.tmp')) continue;
      final stat = await entity.stat();
      total += stat.size;
      files.add((file: entity, bytes: stat.size, modified: stat.modified));
    }
    if (total <= _maxCacheBytes) return;
    files.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in files) {
      if (entry.file.path == newest.path) continue;
      await entry.file.delete();
      total -= entry.bytes;
      if (total <= _maxCacheBytes) break;
    }
  } catch (_) {
    // A cache cleanup failure must not block showing the photo.
  }
}
