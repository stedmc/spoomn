import 'package:flutter/material.dart';

import '../../providers/settings_provider.dart';

Color? groupColour(String? group, BoardColorScheme scheme) =>
    scheme.groupColour(group);
