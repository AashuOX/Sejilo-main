import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../auth/account_auth_controller.dart';
import '../../profile/public_profile_page.dart';
import '../../social/hashtag/hashtag_page.dart';
import '../sejilo_theme.dart';

/// Caption text with tappable `#hashtags` and `@mentions`.
///
/// Stateful because each tappable span needs a [TapGestureRecognizer], and a
/// recognizer created inside `build` is never disposed — a caption in a
/// scrolling feed rebuilds constantly, so the old build-time recognizers leaked
/// one object per rebuild per tag.
class HashtagText extends StatefulWidget {
  const HashtagText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    required this.auth,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final AccountAuthController auth;

  /// Hashtags, plus mentions of the usernames the API actually allows:
  /// letters, digits, dots and underscores, with dots only in the middle so a
  /// mention at the end of a sentence ("thanks @maya.") does not swallow the
  /// full stop.
  static final tokenPattern = RegExp(
    r'#\w+|@[A-Za-z0-9_](?:[A-Za-z0-9._]*[A-Za-z0-9_])?',
  );

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _openHashtag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HashtagPage(tag: tag, auth: widget.auth),
      ),
    );
  }

  void _openProfile(String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(username: username, auth: widget.auth),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The recognizers belong to the spans built below, so the previous batch is
    // retired here rather than in didUpdateWidget: any rebuild replaces them.
    _disposeRecognizers();

    final baseStyle = widget.style ?? const TextStyle();
    final linkStyle = baseStyle.copyWith(
      color: SejiloColors.primary,
      fontWeight: FontWeight.w600,
    );

    final spans = <TextSpan>[];
    var start = 0;

    for (final match in HashtagText.tokenPattern.allMatches(widget.text)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: widget.text.substring(start, match.start),
          style: widget.style,
        ));
      }
      final token = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = token.startsWith('#')
            ? () => _openHashtag(token)
            : () => _openProfile(token.substring(1));
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: token, style: linkStyle, recognizer: recognizer));
      start = match.end;
    }

    if (start < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(start), style: widget.style));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      style: widget.style,
    );
  }
}
