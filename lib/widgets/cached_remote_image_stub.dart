import 'package:flutter/painting.dart';

Future<ImageProvider> imageProviderFor(
  String url, {
  int? cacheWidth,
  String? fallbackUrl,
}) async =>
    cacheWidth == null
        ? NetworkImage(url)
        : ResizeImage(NetworkImage(url), width: cacheWidth);
