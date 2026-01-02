import 'dart:io';
import 'dart:async';
import 'package:path/path.dart';

import 'package:flutter_hbb/models/ffi_model.dart';

Timer periodicImmediate(
    Duration duration, Future<void> Function(Timer? timer) callback) {
  Future.delayed(Duration.zero, () => callback(null));
  return Timer.periodic(duration, (timer) async {
    await callback(timer);
  });
}

Future<String> getHomeDir() async {
  String? home;

  if (Platform.isWindows) {
    home = Platform.environment['USERPROFILE'];
    if (home == null) {
      final drive = Platform.environment['HOMEDRIVE'];
      final path = Platform.environment['HOMEPATH'];

      if (drive != null && path != null) {
        home = join(drive, path);
      }
    }
  } else {
    home = Platform.environment['HOME'];
  }

  if (home == null) {
    final String exePath = Platform.resolvedExecutable;
    home = File(exePath).parent.path.split('\\').sublist(0, 3).join('\\');
  }

  return join(home, await bind.mainGetAppName());
}

String getOsUsername() {
  if (Platform.isWindows) {
    return Platform.environment['USERNAME'] ?? 'unknown';
  }

  return Platform.environment['USER'] ??
      Platform.environment['LOGNAME'] ??
      'unknown';
}
