import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import 'package:flutter/material.dart';

import 'package:path/path.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/utils/index.dart';
import 'package:flutter_hbb/models/ffi_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';

enum PermissionStep {
  installDaemon,
  trustProcess,
  inputMonitoring,
  screenRecording,
  audioRecording,
  windowInstall,
  startService,
}

class PermissionModel extends GetxController {
  Rx<bool> isServiceStopped = true.obs;
  Rx<bool> canRecordAudio = false.obs;
  Rx<bool> isInstalledDaemon = false.obs;
  Rx<bool> isProcessTrusted = false.obs;
  Rx<bool> isInputMonitoring = false.obs;
  Rx<bool> isCanScreenRecording = false.obs;
  Rx<bool> windowInstalled = false.obs;

  @protected
  PermissionStep? currentPermissionStep;
  @protected
  PermissionStep permissionStep = Platform.isMacOS
      ? PermissionStep.trustProcess
      : PermissionStep.windowInstall;

  @protected
  Timer? scheduler;

  PermissionModel() {
    windowInstalled.value = bind.mainIsInstalled();
    isProcessTrusted.value = bind.mainIsProcessTrusted(prompt: false);
    isInputMonitoring.value = bind.mainIsCanInputMonitoring(prompt: false);
    isCanScreenRecording.value = bind.mainIsCanScreenRecording(prompt: false);
    isInstalledDaemon.value = bind.mainIsInstalledDaemon(prompt: false);
    if (Platform.isMacOS) {
      platformChannel.osxCanRecordAudio().then((value) =>
          canRecordAudio.value = value == PermissionAuthorizeType.authorized);
    }
    mainGetBoolOption(GlobalOptions.stopService)
        .then((value) => isServiceStopped.value = value);
  }

  Future<bool> canStartService() async {
    if (Platform.isMacOS) {
      final bool value = bind.mainIsProcessTrusted(prompt: false) &&
          bind.mainIsCanInputMonitoring(prompt: false) &&
          bind.mainIsCanScreenRecording(prompt: false) &&
          bind.mainIsInstalledDaemon(prompt: false);

      if (Platform.isMacOS) {
        return value &&
            (await platformChannel.osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized);
      }
      return value;
    } else if (Platform.isWindows) {
      return bind.mainIsInstalled();
    } else {
      return false;
    }
  }

  Future<bool> requestPermissions() {
    final Completer<bool> completer = Completer();
    scheduler = periodicImmediate(Duration(seconds: 1), (timer) async {
      if (timer != null && await canStartService()) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(true);
        return;
      }

      switch (permissionStep) {
        case PermissionStep.trustProcess:
          if (isProcessTrusted.value) {
            permissionStep = PermissionStep.inputMonitoring;
          } else if (currentPermissionStep != PermissionStep.trustProcess) {
            currentPermissionStep = PermissionStep.trustProcess;
            isProcessTrusted.value = bind.mainIsProcessTrusted(prompt: true);
          }
          break;
        case PermissionStep.inputMonitoring:
          if (isInputMonitoring.value) {
            permissionStep = PermissionStep.screenRecording;
          } else if (currentPermissionStep != PermissionStep.inputMonitoring) {
            currentPermissionStep = PermissionStep.inputMonitoring;
            isInputMonitoring.value =
                bind.mainIsCanInputMonitoring(prompt: true);
          }
          break;
        case PermissionStep.screenRecording:
          if (isCanScreenRecording.value) {
            permissionStep = PermissionStep.audioRecording;
          } else if (currentPermissionStep != PermissionStep.screenRecording) {
            currentPermissionStep = PermissionStep.screenRecording;
            isCanScreenRecording.value =
                bind.mainIsCanScreenRecording(prompt: true);
          }
          break;
        case PermissionStep.audioRecording:
          if (Platform.isMacOS) {
            if (canRecordAudio.value) {
              permissionStep = PermissionStep.installDaemon;
            } else if (currentPermissionStep != PermissionStep.audioRecording) {
              currentPermissionStep = PermissionStep.audioRecording;
              await platformChannel.osxRequestAudio();
              Future.microtask(() async {
                canRecordAudio.value =
                    (await (platformChannel.osxCanRecordAudio()) ==
                        PermissionAuthorizeType.authorized);
              });
            }
          } else {
            permissionStep = PermissionStep.installDaemon;
          }
        case PermissionStep.installDaemon:
          if (isInstalledDaemon.value) {
            permissionStep = PermissionStep.startService;
          } else if (currentPermissionStep != PermissionStep.installDaemon) {
            currentPermissionStep = PermissionStep.installDaemon;
            isInstalledDaemon.value = bind.mainIsInstalledDaemon(prompt: true);
          }
        case PermissionStep.startService:
          if (isServiceStopped.value) {
            isServiceStopped.value =
                (await mainGetBoolOption(GlobalOptions.stopService));
          }
          break;
        case PermissionStep.windowInstall:
          if (!windowInstalled.value &&
              currentPermissionStep != PermissionStep.windowInstall) {
            currentPermissionStep = PermissionStep.windowInstall;
            final String exePath = Platform.resolvedExecutable;
            final String exeDir = File(exePath).parent.path;
            await bind.installInstallMe(
                options: 'desktopicon startmenu',
                path: join(exeDir, await bind.mainGetAppName()));
          }
          break;
      }
    });

    return completer.future;
  }

  @override
  void dispose() {
    scheduler?.cancel();
    super.dispose();
  }
}
