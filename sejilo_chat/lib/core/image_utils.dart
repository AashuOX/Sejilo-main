// image_utils.dart — upload-side image optimiser.
//
// Scales a camera photo down to feed dimensions and re-encodes it as JPEG so
// the payload fits the API's media ceiling (~2 MB of real bytes; see
// backend/src/common/dto/media-payload.dto.ts).
//
// This runs on `package:image` rather than `dart:ui` on purpose: dart:ui can
// only encode PNG, so the previous implementation turned a 4 MB camera JPEG
// into a *larger* PNG, and let anything under 300 KB through untouched. Both
// paths produced bodies the server rejected.
//
// The work happens in a background isolate via `compute`, because decoding a
// 12-megapixel image in pure Dart takes long enough to drop frames.

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Bytes ready to upload, together with the MIME type that actually describes
/// them.
///
/// Returning the two together is the point of this class: every call site used
/// to guess the type separately — and mostly guessed wrong, labelling PNG bytes
/// as `image/jpeg` — while the backend reads the label to decide how to serve
/// the file back.
@immutable
class OptimizedImage {
  const OptimizedImage(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;

  int get sizeBytes => bytes.length;
}

abstract final class ImageUtils {
  /// Longest edge for feed posts and stories.
  static const int maxPostDimension = 1080;

  /// Longest edge used when the device has upload quality turned down.
  ///
  /// Roughly halves the uploaded bytes of a typical photo, which is the whole
  /// point of the setting: less mobile data spent per post.
  static const int dataSaverPostDimension = 720;

  /// Longest edge for profile avatars.
  static const int maxAvatarDimension = 512;

  /// Byte ceiling aimed for after encoding.
  ///
  /// base64url inflates this by 4/3 on the wire, so 1.5 MB becomes ~2 MB —
  /// inside the server's 3 MB string limit with room to spare.
  static const int maxTargetSizeBytes = 1500 * 1024;

  /// Smallest longest-edge the size loop will shrink to before giving up.
  static const int minDimension = 320;

  static const int _startJpegQuality = 88;
  static const int _minJpegQuality = 45;
  static const int _qualityStep = 12;

  /// Returns [rawBytes] downscaled and re-encoded when it is too big, along
  /// with the MIME type of whatever comes back.
  ///
  /// Never throws: an undecodable or unrecognised image is handed back as-is so
  /// a picker failure cannot take the compose screen down with it. The server
  /// still validates, so the worst case is a 400 the UI can show.
  static Future<OptimizedImage> optimizeImage(
    Uint8List rawBytes, {
    int maxDimension = maxPostDimension,
  }) async {
    if (rawBytes.isEmpty) {
      return OptimizedImage(rawBytes, 'application/octet-stream');
    }
    try {
      return await compute(
        _optimizeInIsolate,
        _OptimizeRequest(rawBytes, maxDimension),
      );
    } catch (_) {
      return OptimizedImage(
        rawBytes,
        sniffMimeType(rawBytes) ?? 'application/octet-stream',
      );
    }
  }

  /// Best-effort MIME type from the file's magic bytes.
  ///
  /// Returns null for formats the API does not accept, which is the signal to
  /// re-encode rather than pass through.
  static String? sniffMimeType(Uint8List bytes) =>
      _mimeForFormat(_detectFormat(bytes));
}

/// Identifies the container without letting a malformed file escape as an
/// exception.
///
/// `findFormatForData` offers the bytes to every decoder's `isValidFile`, and
/// some of them — PSD, for one — read a fixed-size header without checking the
/// length first, so a five-byte input throws RangeError instead of answering
/// "not mine".
img.ImageFormat _detectFormat(Uint8List bytes) {
  try {
    return img.findFormatForData(bytes);
  } catch (_) {
    return img.ImageFormat.invalid;
  }
}

/// Maps a decoded format to a MIME type the API accepts, or null when it does
/// not accept it at all (BMP, TIFF, PSD…).
String? _mimeForFormat(img.ImageFormat format) => switch (format) {
      img.ImageFormat.jpg => 'image/jpeg',
      img.ImageFormat.png => 'image/png',
      img.ImageFormat.gif => 'image/gif',
      img.ImageFormat.webp => 'image/webp',
      _ => null,
    };

@immutable
class _OptimizeRequest {
  const _OptimizeRequest(this.bytes, this.maxDimension);

  final Uint8List bytes;
  final int maxDimension;
}

/// Isolate entry point. Must stay a top-level function for `compute`.
OptimizedImage _optimizeInIsolate(_OptimizeRequest request) {
  final raw = request.bytes;
  final sourceMime = _mimeForFormat(_detectFormat(raw));

  img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } catch (_) {
    // A truncated or hand-crafted file can trip a decoder mid-way.
    decoded = null;
  }
  if (decoded == null) {
    // Unsupported container, or a video the caller handed to the wrong helper.
    // Passing the bytes through unchanged keeps this non-destructive.
    return OptimizedImage(raw, sourceMime ?? 'application/octet-stream');
  }

  final withinBounds =
      decoded.width <= request.maxDimension && decoded.height <= request.maxDimension;

  // Already small enough in both senses: return the original file. This is the
  // only path that preserves an animated GIF or WebP, since re-encoding flattens
  // it to a single frame.
  if (withinBounds &&
      raw.length <= ImageUtils.maxTargetSizeBytes &&
      sourceMime != null) {
    return OptimizedImage(raw, sourceMime);
  }

  // `package:image` does not apply the EXIF orientation tag on decode, so a
  // portrait phone photo would come out on its side once re-encoded — the tag
  // travels with the original file but not with our output.
  var working = img.bakeOrientation(decoded);

  if (working.width > request.maxDimension ||
      working.height > request.maxDimension) {
    final landscape = working.width >= working.height;
    working = img.copyResize(
      working,
      // Passing one edge lets copyResize keep the aspect ratio itself.
      width: landscape ? request.maxDimension : null,
      height: landscape ? null : request.maxDimension,
      interpolation: img.Interpolation.average,
    );
  }

  var quality = ImageUtils._startJpegQuality;
  var encoded = img.encodeJpg(working, quality: quality);

  // Trade quality first — it is invisible long before it is cheap — then pixels.
  while (encoded.length > ImageUtils.maxTargetSizeBytes) {
    if (quality > ImageUtils._minJpegQuality) {
      quality = (quality - ImageUtils._qualityStep)
          .clamp(ImageUtils._minJpegQuality, ImageUtils._startJpegQuality);
    } else {
      final nextWidth = (working.width * 0.75).round();
      final nextHeight = (working.height * 0.75).round();
      if (nextWidth < ImageUtils.minDimension ||
          nextHeight < ImageUtils.minDimension) {
        break;
      }
      working = img.copyResize(
        working,
        width: nextWidth,
        interpolation: img.Interpolation.average,
      );
    }
    encoded = img.encodeJpg(working, quality: quality);
  }

  return OptimizedImage(encoded, 'image/jpeg');
}
