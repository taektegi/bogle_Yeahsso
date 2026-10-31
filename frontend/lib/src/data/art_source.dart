import '../util/art_cache.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Where a friend's artwork comes from. Bundled friends use assets; ones
/// made with or without the character service are files kept on the iPad;
/// any other picture may be an http(s) URL. Every place that reads a
/// friend's artwork goes through here, so all of them work alike, as SVG or
/// as a raster image.
enum ArtOrigin { asset, file, network }

ArtOrigin artOriginOf(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return ArtOrigin.network;
  }
  if (path.startsWith('file://') || path.startsWith('/')) return ArtOrigin.file;
  return ArtOrigin.asset;
}

/// The path without a URL's query or fragment, for telling its type.
String _bare(String path) => path.split(RegExp('[?#]')).first.toLowerCase();

bool isSvgArt(String path) => _bare(path).endsWith('.svg');

bool isPngArt(String path) => _bare(path).endsWith('.png');

String _filePath(String path) =>
    path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;

/// The artwork's bytes, from wherever it is. A cut-out PNG comes cut to its
/// figure (see [artCropOf]).
Future<Uint8List> loadArtBytes(String path) async {
  if (!isPngArt(path)) return _rawArtBytes(path);
  final figure = await _figure(path);
  // Read again rather than keep a failed read: each caller gets its own
  // error, and a picture that comes back later is found.
  return figure?.bytes ?? _rawArtBytes(path);
}

Future<Uint8List> _rawArtBytes(String path) async =>
    switch (artOriginOf(path)) {
      ArtOrigin.asset => (await rootBundle.load(path)).buffer.asUint8List(),
      ArtOrigin.file => File(_filePath(path)).readAsBytes(),
      ArtOrigin.network => (await NetworkAssetBundle(
        Uri.parse(path),
      ).load('')).buffer.asUint8List(),
    };

Future<String> loadArtString(String path) async =>
    utf8.decode(await loadArtBytes(path));

/// A raster artwork as an image provider. A PNG is shown as
/// [loadArtBytes] gives it, cut to its figure.
ImageProvider artImage(String path) => isPngArt(path)
    ? FriendArtImage(path)
    : switch (artOriginOf(path)) {
        ArtOrigin.asset => AssetImage(path),
        ArtOrigin.file => FileImage(File(_filePath(path))),
        ArtOrigin.network => NetworkImage(path),
      };

/// An SVG artwork as a picture loader.
BytesLoader artSvgLoader(String path) => switch (artOriginOf(path)) {
  ArtOrigin.asset => SvgAssetLoader(path),
  ArtOrigin.file => SvgFileLoader(File(_filePath(path))),
  ArtOrigin.network => SvgNetworkLoader(path),
};

/// A file next to the artwork: `dduchi.png` → `dduchi.face.json`.
String artSibling(String path, String from, String to) {
  final cut = path.indexOf(RegExp('[?#]'));
  final head = cut < 0 ? path : path.substring(0, cut);
  final tail = cut < 0 ? '' : path.substring(cut);
  return '${head.replaceFirst(RegExp('${RegExp.escape(from)}\$'), to)}$tail';
}

/// Width ÷ height of artwork measured so far, by path, for laying out its
/// drawing without waiting (a friend's flight between card and house).
final artAspects = ArtCache<String, double>(96);

/// The part of a cut-out PNG that the friend is read as, in fractions of the
/// whole picture, or null when the picture is used as it is.
///
/// A friend stands bottom-centred in its square in the house, so empty
/// space under its feet leaves it floating. A generator hands over its
/// character in the middle of a square, clear canvas; such a picture is cut
/// down to the figure, right to the bottom of its feet, with a little air
/// on the other sides. Snug pictures, and ones with a ground of their own
/// (photos, painted backgrounds), are left as they are. Face maps are moved
/// along (see `faceMapFor`).
Future<Rect?> artCropOf(String path) async =>
    isPngArt(path) ? (await _figure(path))?.crop : null;

typedef _Figure = ({Uint8List bytes, Rect? crop});

final _figures = ArtCache<String, Future<_Figure?>>(
  24,
  maxWeight: 24 * 1024 * 1024,
);

/// The picture as it's shown, or null when it can't be read (not kept, so
/// it's tried again next time).
Future<_Figure?> _figure(String path) async {
  final figure = await (_figures[path] ??= _cut(path));
  if (figure == null) {
    _figures.remove(path);
  } else {
    _figures.setWeight(path, figure.bytes.length);
  }
  return figure;
}

/// Opaque enough to count as the figure: a generator's faint halo or a
/// soft shadow under the feet does not.
const _figureAlpha = 64;

Future<_Figure?> _cut(String path) async {
  final Uint8List raw;
  try {
    raw = await _rawArtBytes(path);
  } on Object {
    return null;
  }
  try {
    final codec = await ui.instantiateImageCodec(raw);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final rgba = await image.toByteData();
      if (rgba == null) return (bytes: raw, crop: null);
      final w = image.width, h = image.height;
      final found = await compute(_figureBounds, (
        rgba.buffer.asUint8List(),
        w,
      ));
      if (found == null) return (bytes: raw, crop: null);
      final (left, top, right, bottom) = found;
      final air = math.max(
        2,
        (math.max(right - left, bottom - top) * .02).ceil(),
      );
      final crop = Rect.fromLTRB(
        math.max(0, left - air).toDouble(),
        math.max(0, top - air).toDouble(),
        math.min(w, right + 1 + air).toDouble(),
        // Anti-aliasing below the last solid row, and no more.
        math.min(h, bottom + 2).toDouble(),
      );
      if (crop.width > w * .99 && crop.height > h * .99) {
        return (bytes: raw, crop: null);
      }
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        crop,
        Rect.fromLTWH(0, 0, crop.width, crop.height),
        Paint()..filterQuality = ui.FilterQuality.none,
      );
      final picture = recorder.endRecording();
      final cut = await picture.toImage(
        crop.width.round(),
        crop.height.round(),
      );
      picture.dispose();
      try {
        final png = await cut.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return (bytes: raw, crop: null);
        return (
          bytes: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          crop: Rect.fromLTRB(
            crop.left / w,
            crop.top / h,
            crop.right / w,
            crop.bottom / h,
          ),
        );
      } finally {
        cut.dispose();
      }
    } finally {
      image.dispose();
    }
  } on Object {
    // Not decodable here: shown (or not) as it is.
    return (bytes: raw, crop: null);
  }
}

/// The first and last columns and rows of the figure, or null when the
/// picture has a ground of its own (two or more opaque corners) or nothing
/// solid at all.
(int, int, int, int)? _figureBounds((Uint8List, int) picture) {
  final (rgba, w) = picture;
  final h = rgba.length ~/ (w * 4);
  bool solid(int x, int y) => rgba[(y * w + x) * 4 + 3] >= _figureAlpha;
  final opaqueCorners = [
    (0, 0),
    (w - 1, 0),
    (0, h - 1),
    (w - 1, h - 1),
  ].where((c) => solid(c.$1, c.$2)).length;
  if (opaqueCorners >= 2) return null;
  var left = w, top = h, right = -1, bottom = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!solid(x, y)) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      bottom = y;
    }
  }
  return right < 0 ? null : (left, top, right, bottom);
}

/// A PNG friend as [loadArtBytes] gives it (cut to its figure), for [Image].
class FriendArtImage extends ImageProvider<FriendArtImage> {
  const FriendArtImage(this.path);
  final String path;

  @override
  Future<FriendArtImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    FriendArtImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: loadArtBytes(key.path).then(
      (bytes) async => decode(await ui.ImmutableBuffer.fromUint8List(bytes)),
    ),
    scale: 1,
    debugLabel: key.path,
  );

  @override
  bool operator ==(Object other) =>
      other is FriendArtImage && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
