import 'package:flutter/material.dart';

/// A small pill badge on a post — `LATE` (red) or `HOUSE` (grey), currently.
class PostBadge extends StatelessWidget {
  final String label;
  final Color color;

  const PostBadge(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.6,
          color: Colors.white,
        ),
      ),
    );
  }
}
