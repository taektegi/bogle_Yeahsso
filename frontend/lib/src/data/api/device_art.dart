import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../screens/house/face_map.dart';

/// A friend's pictures kept on the iPad: the artwork, its thumbnail and its
/// face map, side by side so the house finds the face map next to the
/// picture (`x.png` → `x.face.json`), with no network once they are here.
class DeviceArt {
  const DeviceArt(this.folder);

  /// Usually `<Application Support>/bogle/art`.
  final Directory folder;

  /// Saves the pictures for [name] (a friend or a generation job) and
  /// returns where the artwork and the thumbnail are.
  Future<({String art, String? thumbnail})> keep(
    String name, {
    required Uint8List art,
    Uint8List? thumbnail,
    Object? face,
  }) async {
    // 확장자나 응답 헤더만 믿지 않고 실제 PNG를 확인한 뒤 파일로 남긴다.
    await _validatePng(art);
    if (thumbnail != null) await _validatePng(thumbnail);
    await folder.create(recursive: true);
    final artFile = File('${folder.path}/$name.png');
    await artFile.writeAsBytes(art, flush: true);
    String? thumbPath;
    if (thumbnail != null) {
      final thumbFile = File('${folder.path}/$name.thumb.png');
      await thumbFile.writeAsBytes(thumbnail, flush: true);
      thumbPath = thumbFile.path;
    }
    if (face != null) {
      await File(
        '${folder.path}/$name.face.json',
      ).writeAsString(jsonEncode(face), flush: true);
      giveFaceMap(artFile.path, face);
    }
    return (art: artFile.path, thumbnail: thumbPath);
  }

  /// 그림보다 늦게 온 [name]의 얼굴 좌표를 그림 옆에 저장한다.
  /// 친구를 지워 그림이 더 이상 없으면 아무것도 남기지 않는다.
  Future<void> keepFace(String name, Object face) async {
    final artFile = File('${folder.path}/$name.png');
    if (!await artFile.exists()) return;
    await File(
      '${folder.path}/$name.face.json',
    ).writeAsString(jsonEncode(face), flush: true);
    giveFaceMap(artFile.path, face);
  }

  static Future<void> _validatePng(Uint8List bytes) async {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length ||
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).contains(false)) {
      throw const FormatException('친구 그림은 PNG 형식이어야 해요.');
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        if (codec.frameCount != 1) throw const FormatException();
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (_) {
      throw const FormatException('친구 그림을 읽을 수 없어요. 다시 만들어 주세요.');
    }
  }

  /// Removes a friend's pictures: the artwork at [artPath] (if it is one
  /// of the files kept here), its thumbnail and its face map.
  Future<void> forget(String artPath) async {
    if (!artPath.startsWith(folder.path) || !artPath.endsWith('.png')) return;
    final stem = artPath.substring(0, artPath.length - '.png'.length);
    for (final path in ['$stem.png', '$stem.thumb.png', '$stem.face.json']) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Gone or busy: a stray file doesn't matter.
      }
    }
  }
}
