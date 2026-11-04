import 'package:flutter/material.dart';

import 'cached_remote_image_stub.dart'
    if (dart.library.io) 'cached_remote_image_io.dart' as cache;

/// Displays public Supabase photos and keeps a bounded on-disk cache on mobile.
class CachedRemoteImage extends StatefulWidget {
  const CachedRemoteImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth = 512,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  State<CachedRemoteImage> createState() => _CachedRemoteImageState();
}

class _CachedRemoteImageState extends State<CachedRemoteImage> {
  late Future<ImageProvider> _provider;

  @override
  void initState() {
    super.initState();
    _provider = cache.imageProviderFor(widget.url, cacheWidth: widget.cacheWidth);
  }

  @override
  void didUpdateWidget(CachedRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _provider = cache.imageProviderFor(widget.url, cacheWidth: widget.cacheWidth);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ImageProvider>(
    future: _provider,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return widget.errorBuilder?.call(
              context,
              snapshot.error!,
              snapshot.stackTrace,
            ) ??
            const Icon(Icons.broken_image);
      }
      if (!snapshot.hasData) {
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return Image(
        image: snapshot.data!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        loadingBuilder: widget.loadingBuilder,
        errorBuilder: widget.errorBuilder,
      );
    },
  );
}
