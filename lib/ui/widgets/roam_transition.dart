import 'package:flutter/material.dart';

/// A bounded, responsive rendering of the latest AP transition.
///
/// AP names are user-controlled and can be arbitrarily long. Unlike a generic
/// metric tile, both sides receive an explicit width and at most two lines, so
/// the transition can never grow beyond its card.
class RoamTransition extends StatelessWidget {
  final String label;
  final String from;
  final String to;

  const RoamTransition({
    super.key,
    required this.label,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$from → $to',
      child: Semantics(
        label: '$label: $from → $to',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2530),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  color: Color(0xFF7D8590),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth < 280 ? _vertical() : _horizontal(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _horizontal() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _name(from, TextAlign.right)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 9),
            child:
                Icon(Icons.arrow_forward, size: 18, color: Color(0xFF7D8590)),
          ),
          Expanded(child: _name(to, TextAlign.left)),
        ],
      );

  Widget _vertical() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _name(from, TextAlign.left),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child:
                Icon(Icons.arrow_downward, size: 17, color: Color(0xFF7D8590)),
          ),
          _name(to, TextAlign.left),
        ],
      );

  Widget _name(String value, TextAlign align) => Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        textAlign: align,
        style: const TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      );
}
