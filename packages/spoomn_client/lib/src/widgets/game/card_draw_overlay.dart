import 'package:flutter/material.dart';

class CardDrawOverlay extends StatefulWidget {
  const CardDrawOverlay({
    super.key,
    required this.entry,
    required this.onDismiss,
  });

  final Map<String, dynamic> entry;
  final VoidCallback onDismiss;

  @override
  State<CardDrawOverlay> createState() => _CardDrawOverlayState();
}

class _CardDrawOverlayState extends State<CardDrawOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
        ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = (widget.entry['payload'] as Map<String, dynamic>?) ?? {};
    final deck = payload['deck'] as String? ?? '';
    final label = payload['label'] as String? ?? payload['card_id'] as String? ?? 'Card';
    final isChance = deck.contains('chance');
    final faceColor = isChance ? const Color(0xFFFF6B6B) : const Color(0xFFF4A435);
    final bgColor = isChance ? const Color(0xFFFFECEC) : const Color(0xFFFFF9E6);
    final deckLabel = isChance ? 'CHANCE' : 'COMMUNITY CHEST';

    return GestureDetector(
      onTap: widget.onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black45,
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: _CardFace(
                deckLabel: deckLabel,
                label: label,
                faceColor: faceColor,
                bgColor: bgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.deckLabel,
    required this.label,
    required this.faceColor,
    required this.bgColor,
  });

  final String deckLabel;
  final String label;
  final Color faceColor;
  final Color bgColor;

  static ({String title, String body}) _splitLabel(String label) {
    int idx = label.indexOf('. ');
    if (idx < 0) idx = label.indexOf('! ');
    if (idx >= 0) {
      return (
        title: label.substring(0, idx + 1).trim(),
        body: label.substring(idx + 2).trim(),
      );
    }
    return (title: label.replaceAll(RegExp(r'\.$'), '').trim(), body: '');
  }

  @override
  Widget build(BuildContext context) {
    final (:title, :body) = _splitLabel(label);

    return Card(
      elevation: 20,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: faceColor, width: 3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: faceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Text(
                deckLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: body.isEmpty ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: faceColor.withValues(alpha: 0.4), thickness: 1),
                    ),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Tap to dismiss',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
