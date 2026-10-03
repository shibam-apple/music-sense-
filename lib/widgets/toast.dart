import 'dart:async';

import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import '../theme/tokens.dart';

/// A small Metro-style message that slides in above the XMB bar and
/// leaves after a few seconds.
class PlayerToast extends StatefulWidget {
  const PlayerToast({super.key});

  @override
  State<PlayerToast> createState() => _PlayerToastState();
}

class _PlayerToastState extends State<PlayerToast> {
  ValueNotifier<String?>? _source;
  String? _text;
  Timer? _hide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = PlayerScope.of(context).message;
    if (source != _source) {
      _source?.removeListener(_show);
      _source = source..addListener(_show);
    }
  }

  void _show() {
    final text = _source?.value;
    if (text == null) return;
    setState(() => _text = text);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _text = null);
      _source?.value = null;
    });
  }

  @override
  void dispose() {
    _source?.removeListener(_show);
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _text != null;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.6),
        duration: MsMotion.medium,
        curve: MsMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: MsMotion.fast,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: MsSizes.pageInset),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: MsColors.tileDark,
              borderRadius: BorderRadius.circular(MsSizes.tileRadius),
            ),
            child: Text(
              _text ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MsText.rowSubtitle.copyWith(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
