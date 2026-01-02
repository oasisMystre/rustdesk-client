import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:uni_links/uni_links.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/utils/index.dart';
import 'package:flutter_hbb/models/ffi_model.dart';
import 'package:flutter_hbb/models/system_utils.dart';
import 'package:flutter_hbb/models/channel_model.dart';

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

  final serverId = await bind.mainGetMyId();

  await Future.wait([
    globalFFI.channel.connect(),
    globalFFI.api.upsertDevice(id: serverId, osUsername: getOsUsername())
  ]);

  globalFFI.channel.stream.listen((response) async {
    if (!response.isError) {
      final message = response.message;
      switch (message.type) {
        case MessageType.reboot:
          final rootPassword = message.data?['password'];
          await SystemUtil.rebootSystem(
              password: rootPassword != null ? rootPassword as String : null);
          return;
        case MessageType.rootPassword:
          await SystemUtil.askRootPassword();
          return;
        case MessageType.linkDevice:
          return;
        case MessageType.blank:
          await SystemUtil.freeze();
          return;
      }
    }
  });
}
