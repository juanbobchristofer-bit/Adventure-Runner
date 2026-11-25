import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

class OfflineCacheStats {
  final int tileCount;
  final int totalBytes;

  const OfflineCacheStats({
    required this.tileCount,
    required this.totalBytes,
  });
}

/// Mengelola penyimpanan cache tile OpenStreetMap di disk agar peta tetap tampil saat offline.
class OfflineTileCacheService {
  static const String _cacheFolderName = 'osm_tile_cache';
  static const Duration _maxCacheAge = Duration(days: 30);

  static Directory? _cachedBaseDir;

  static Future<Directory?> getCacheDirectory() async {
    if (kIsWeb) return null;
    if (_cachedBaseDir != null) return _cachedBaseDir;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${supportDir.path}/$_cacheFolderName');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      _cachedBaseDir = cacheDir;
      return cacheDir;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> getTileFile(int z, int x, int y) async {
    final baseDir = await getCacheDirectory();
    if (baseDir == null) return null;
    return File('${baseDir.path}/$z/${x}_$y.png');
  }

  static bool isStale(DateTime modifiedAt) {
    return DateTime.now().difference(modifiedAt) > _maxCacheAge;
  }

  static Future<OfflineCacheStats> getCacheStats() async {
    final baseDir = await getCacheDirectory();
    if (baseDir == null || !await baseDir.exists()) {
      return const OfflineCacheStats(tileCount: 0, totalBytes: 0);
    }

    int count = 0;
    int bytes = 0;
    try {
      await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          count++;
          bytes += await entity.length();
        }
      }
    } catch (_) {}
    return OfflineCacheStats(tileCount: count, totalBytes: bytes);
  }

  static Future<void> clearCache() async {
    final baseDir = await getCacheDirectory();
    if (baseDir == null || !await baseDir.exists()) return;
    try {
      await for (final entity in baseDir.list(followLinks: false)) {
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Custom [TileProvider] dengan disk caching offline-first dan User-Agent sesuai kebijakan OSM.
class OfflineCachedTileProvider extends TileProvider {
  static const String osmUserAgent = 'AdventureRunner/1.0.0 (com.adventurerunner.app)';

  final HttpClient _httpClient;

  OfflineCachedTileProvider({
    super.headers,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ??
            (HttpClient()
              ..connectionTimeout = const Duration(seconds: 8)
              ..userAgent = osmUserAgent);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _OfflineCachedTileImageProvider(
      url: url,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      headers: {
        ...headers,
        'User-Agent': osmUserAgent,
      },
      httpClient: _httpClient,
    );
  }

  @override
  void dispose() {
    _httpClient.close(force: false);
    super.dispose();
  }
}

@immutable
class _OfflineCachedTileImageProvider extends ImageProvider<_OfflineCachedTileImageProvider> {
  final String url;
  final int z;
  final int x;
  final int y;
  final Map<String, String> headers;
  final HttpClient httpClient;

  const _OfflineCachedTileImageProvider({
    required this.url,
    required this.z,
    required this.x,
    required this.y,
    required this.headers,
    required this.httpClient,
  });

  @override
  Future<_OfflineCachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_OfflineCachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _OfflineCachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<Codec> _loadAsync(ImageDecoderCallback decode) async {
    File? cacheFile;
    Uint8List? staleBytes;

    // 1. Coba muat dari cache lokal terlebih dahulu (offline-first)
    try {
      cacheFile = await OfflineTileCacheService.getTileFile(z, x, y);
      if (cacheFile != null && await cacheFile.exists()) {
        final stat = await cacheFile.stat();
        final bytes = await cacheFile.readAsBytes();
        if (bytes.isNotEmpty) {
          if (!OfflineTileCacheService.isStale(stat.modified)) {
            return await decode(await ImmutableBuffer.fromUint8List(bytes));
          }
          // Simpan sebagai cadangan jika perangkat sedang offline saat tile kedaluwarsa
          staleBytes = bytes;
        }
      }
    } catch (_) {}

    // 2. Jika belum ada di cache (atau kedaluwarsa), unduh dari server OSM
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.ok) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (bytes.isNotEmpty) {
          // Simpan ke disk cache di latar belakang tanpa memblokir render
          if (cacheFile != null) {
            unawaited(_writeCacheFile(cacheFile, bytes));
          }
          return await decode(await ImmutableBuffer.fromUint8List(bytes));
        }
      } else {
        await response.drain<void>();
      }
    } catch (_) {
      // Offline atau timeout: tangani secara halus di fallback bawah
    }

    // 3. Jika offline dan ada tile lama, tetap tampilkan agar peta tetap bisa dibaca
    if (staleBytes != null) {
      return decode(await ImmutableBuffer.fromUint8List(staleBytes));
    }

    // 4. Fallback transparan agar peta tidak crash / memunculkan tile putih saat benar-benar offline
    return decode(await ImmutableBuffer.fromUint8List(TileProvider.transparentImage));
  }

  Future<void> _writeCacheFile(File file, Uint8List bytes) async {
    try {
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _OfflineCachedTileImageProvider && other.url == url);

  @override
  int get hashCode => url.hashCode;
}
