import 'package:flutter/material.dart';

Color? groupColour(String? group) => switch (group) {
  'brown'     => const Color(0xFF955436),
  'lightBlue' => const Color(0xFFAAE0FA),
  'pink'      => const Color(0xFFD93A96),
  'orange'    => const Color(0xFFF7941D),
  'red'       => const Color(0xFFED1B24),
  'yellow'    => const Color(0xFFFEF200),
  'green'     => const Color(0xFF1FB25A),
  'darkBlue'  => const Color(0xFF0072BB),
  _           => null,
};
