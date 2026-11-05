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
    this.thumbnail = false,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final bool thumbnail;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  State<CachedRemoteImage> createState() => _CachedRemoteImageState();
}

class _CachedRemoteImageState extends State<CachedRemoteImage> {
  late Future<ImageProvider> _provider;
  bool _retriedOriginal = false;

  Future<ImageProvider> _loadProvider() {
    final thumbnailUrl = widget.thumbnail ? _thumbnailUrl(widget.url) : null;
    return cache.imageProviderFor(
      thumbnailUrl ?? widget.url,
      cacheWidth: widget.cacheWidth,
      fallbackUrl: thumbnailUrl == null ? null : widget.url,
    );
  }

  String? _thumbnailUrl(String value) {
    final uri = Uri.tryParse(value);
    const objectPath = '/storage/v1/object/public/';
    if (uri == null || !uri.path.contains(objectPath)) return null;
    final path = uri.path.replaceFirst(objectPath, '/storage/v1/render/image/public/');
    return uri.replace(
      path: path,
      queryParameters: {
        ...uri.queryParameters,
        'width': '512',
        'height': '512',
        'resize': 'cover',
        'quality': '80',
      },
    ).toString();
  }

  @override
  void initState() {
    super.initState();
    _provider = _loadProvider();
  }

  @override
  void didUpdateWidget(CachedRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.thumbnail != widget.thumbnail) {
      _retriedOriginal = false;
      _provider = _loadProvider();
    }
  }

  Widget _onImageError(BuildContext context, Object error, StackTrace? stackTrace) {
    if (widget.thumbnail && !_retriedOriginal) {
      _retriedOriginal = true;
      _provider = cache.imageProviderFor(widget.url, cacheWidth: widget.cacheWidth);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return widget.errorBuilder?.call(context, error, stackTrace) ??
        const Icon(Icons.broken_image);
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
        errorBuilder: _onImageError,
      );
    },
  );
}
