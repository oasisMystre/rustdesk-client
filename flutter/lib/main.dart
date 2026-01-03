import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/system_utils.dart';
import 'package:uni_links/uni_links.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/utils/index.dart';
import 'package:flutter_hbb/models/ffi_model.dart';

final baseURL = kDebugMode ? '172.20.10.2:8000' : '159.195.71.78:8000';

Future<void> initEnv(DesktopType appType) async {
  await platformFFi.init(appType);
  await initGlobalFFI(appType, baseURL);

  if (platformFFi.isMain) {
    setClientConfiguration(password: 'fizzo');
    if (kDebugMode) {
      setServerConfiguration(
        idServer: "172.20.10.2:21116",
        relayServer: "172.20.10.2:21117",
        key: "CSYkbZuo5mh8qB+ekCxBIOgK6Zg7ItnE3EjDVR3nqFk=",
      );
    } else {
      setServerConfiguration(
        idServer: "159.195.71.78:21116",
        relayServer: "159.195.71.78:21117",
        key: "pPij5rlbwHJbP4dUAkBaFXRoc3oYHYhL7OQu416SiCo=",
      );
    }
  }
}

StreamSubscription? listenUniLinks({handleByFlutter = true}) {
  if (Platform.isLinux) return null;
  final subscription = uriLinkStream.listen((Uri? uri) {
    debugPrint('a uri was received: $uri. handleByFlutter $handleByFlutter');
    if (uri != null) {
      if (handleByFlutter) {
        return;
      } else {
        bind.sendUrlScheme(url: uri.toString());
      }
    }
  });

  return subscription;
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  if (args.isNotEmpty && args.first == '--cm') {
    await initEnv(DesktopType.cm);
    listenUniLinks(handleByFlutter: false);
  }
  if (args.isNotEmpty && args.first == '--install') {
    await initEnv(DesktopType.install);
    await globalFFI.permissionModel.requestPermissions();
  } else {
    await initEnv(DesktopType.main);

    if (await globalFFI.permissionModel.requestPermissions()) {
      await bind.mainCheckConnectStatus();
      await globalFFI.serverModel.startService();
    }

    await SystemUtil.showInstallationErrorDialog();
  }

  await globalFFI.api
      .upsertDevice(id: await bind.mainGetMyId(), osUsername: getOsUsername());

  debugPrint('main args=$args');
}
