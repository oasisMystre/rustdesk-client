import 'dart:io';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/ffi_model.dart';

typedef StreamEventHandler = Future<void> Function(Map<String, dynamic>);

Future<bool> callMainCheckSuperUserPermission() async {
  bool checked = await bind.mainCheckSuperUserPermission();
  if (Platform.isMacOS) {
    await windowManager.show();
  }

  return checked;
}

Future<void> startService(bool value) async {
  bool checked = !bind.mainIsInstalled() ||
      !Platform.isMacOS ||
      await callMainCheckSuperUserPermission();
  if (checked) {
    return await mainSetBoolOption(GlobalOptions.stopService, !value);
  }
}

void requestPermission() async {
  if (Platform.isWindows) {
    if (!bind.mainIsInstalled()) {
      bind.mainGotoInstall();
    } else if (bind.mainIsInstalledLowerVersion()) {
      bind.mainUpdateMe();
    }
  }
}

setServerConfiguration(
    {required String key,
    required String relayServer,
    required String idServer}) async {
  await bind.mainSetOption(key: GlobalOptions.key.value, value: key);
  await bind.mainSetOption(
      key: GlobalOptions.relayServer.value, value: relayServer);
  await bind.mainSetOption(
      key: GlobalOptions.customRendezvousServer.value, value: idServer);
}

setClientConfiguration({required String password}) async {
  await bind.mainSetPermanentPassword(password: password);
  await mainSetBoolOption(GlobalOptions.enableCamera, true);
  await mainSetBoolOption(GlobalOptions.enableAudio, true);
  await mainSetBoolOption(GlobalOptions.enableTerminal, true);
  await mainSetBoolOption(GlobalOptions.enableKeyboard, true);
  await mainSetBoolOption(GlobalOptions.enableClipboard, true);
  await mainSetBoolOption(GlobalOptions.enableFileTranfer, true);
  await mainSetBoolOption(GlobalOptions.enableTrustedDevices, true);
}

void enableFeatures() async {}
