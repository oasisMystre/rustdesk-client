import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uni_links/uni_links.dart';
import 'package:get/state_manager.dart';
import 'package:get/instance_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
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
  platformFFi.registerEventHandler('native_ui', 'native_ui', (event) async {
    debugPrint("[event] native_ui $event");
  });
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

  debugPrint('$args ---args');
}

class MainApplication extends StatefulWidget {
  const MainApplication({super.key});

  @override
  State<StatefulWidget> createState() => _MainApplicationState();
}

class _MainApplicationState extends State<MainApplication> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    Get.delete<FFIModel>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Obx(() {
          return Column(
            children: [
              TextButton(
                child: Text("Start Service"),
                onPressed: () async {
                  debugPrint(
                      bind.mainIsCanScreenRecording(prompt: true).toString());
                },
              ),
              Column(
                children: [
                  Text(
                      'Service Stopped: ${globalFFI.permissionModel?.isServiceStopped.value}'),
                  Text(
                      'Trusted Process: ${globalFFI.permissionModel?.isProcessTrusted.value}'),
                  Text(
                      'Input monitoring: ${globalFFI.permissionModel?.isInputMonitoring.value}'),
                  Text(
                      'Screen recording: ${globalFFI.permissionModel?.isCanScreenRecording.value}'),
                  Text(
                      'Audio recording: ${globalFFI.permissionModel?.canRecordAudio.value}'),
                  Text(
                      'Daemon Installed: ${globalFFI.permissionModel?.isInstalledDaemon.value}'),
                ],
              )
            ],
          );
        }),
      ),
    );
  }
}
