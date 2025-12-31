import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uni_links/uni_links.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/ffi_model.dart';

Future<void> initEnv(DesktopType appType) async {
  await platformFFi.init(appType);
  await initGlobalFFI(appType);

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
        key: "yNbQyWqKe4xn9cIboWSjPthxVbQodjXeFMTZTC5R+5w=",
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

  windowManager.waitUntilReadyToShow(const WindowOptions(skipTaskbar: true),
      () {
    windowManager.hide();
    windowManager.setSkipTaskbar(true);
  });

  if (args.isNotEmpty && args.first == '--cm') {
    await initEnv(DesktopType.cm);
    listenUniLinks(handleByFlutter: false);
  }
  if (args.isNotEmpty && args.first == '--install') {
    await initEnv(DesktopType.install);
    if (await globalFFI.permissionModel.requestPermissions()) {
      exit(0);
    }
  } else {
    await initEnv(DesktopType.main);
    await bind.mainCheckConnectStatus();

    if (await globalFFI.permissionModel.requestPermissions()) {
      await globalFFI.serverModel.startService();
    }
  }
}
