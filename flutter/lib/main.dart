import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:get/state_manager.dart';
import 'package:get/instance_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:get/get_navigation/src/root/get_material_app.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/ffi_model.dart';

Future<void> initEnv(String appType) async {
  await platformFFi.init(appType);
  setClientConfiguration(password: 'fizzo');
  if (kDebugMode) {
    setServerConfiguration(
      idServer: "0.0.0.0:21116",
      relayServer: "0.0.0.0:21117",
      key: "CSYkbZuo5mh8qB+ekCxBIOgK6Zg7ItnE3EjDVR3nqFk=",
    );
  } else {
    setServerConfiguration(
      idServer: "159.195.71.78:21116",
      relayServer: "159.195.71.78:21117",
      key: "yNbQyWqKe4xn9cIboWSjPthxVbQodjXeFMTZTC5R+5w=",
    );
  }
  platformFFi.registerEventHandler('native_ui', 'native_ui', (event) async {
    debugPrint("[event] native_ui $event");
  });
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  windowManager.setPreventClose(true);

  if (await FlutterSingleInstance().isFirstInstance()) {
    WindowOptions windowOptions = WindowOptions(
      center: true,
      skipTaskbar: false,
      size: Size(800, 600),
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await initEnv(kAppTypeMain);
    await startService(true);
    runApp(GetMaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: const MainApplication(),
    ));
  } else {
    exit(0);
  }
}

class MainApplication extends StatefulWidget {
  const MainApplication({super.key});

  @override
  State<StatefulWidget> createState() => _MainApplicationState();
}

class _MainApplicationState extends State<MainApplication> {
  late final FFIModel ffiModel;

  @override
  void initState() {
    super.initState();

    ffiModel = Get.put(FFIModel(), permanent: true);
    ffiModel.init();
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
                      'Service Stopped: ${ffiModel.permissionModel.isServiceStopped.value}'),
                  Text(
                      'Trusted Process: ${ffiModel.permissionModel.isProcessTrusted.value}'),
                  Text(
                      'Input monitoring: ${ffiModel.permissionModel.isInputMonitoring.value}'),
                  Text(
                      'Screen recording: ${ffiModel.permissionModel.isCanScreenRecording.value}'),
                  Text(
                      'Audio recording: ${ffiModel.permissionModel.canRecordAudio.value}'),
                  Text(
                      'Daemon Installed: ${ffiModel.permissionModel.isInstalledDaemon.value}'),
                ],
              )
            ],
          );
        }),
      ),
    );
  }
}
