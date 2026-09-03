import 'package:flutter/material.dart';

class GameToastBanner extends StatefulWidget {
  const GameToastBanner({super.key, required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;

  @override
  State<GameToastBanner> createState() => _GameToastBannerState();
}

class _GameToastBannerState extends State<GameToastBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _opacity = Tween(begin: 0.0, end: 1.0).animate(_ctrl);
    _slide = Tween(begin: const Offset(0, -0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            widget.message,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
