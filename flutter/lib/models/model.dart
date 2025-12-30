import 'package:flutter_hbb/consts.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/cupertino.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/native_model.dart';
import 'package:flutter_hbb/models/permission_model.dart';

class FFIModel extends GetxController {
  late StateModel stateModel;
  late ServerModel serverModel;
  late PlatformFFi platformFFi;
  late PermissionModel permissionModel;

  late UuidValue sessionId;

  FFIModel(DesktopType desktopType) {
    sessionId = Uuid().v4obj();

    platformFFi = Get.put(PlatformFFi.instance);
    permissionModel = Get.put(PermissionModel());
    stateModel = Get.put(StateModel(desktopType));
    serverModel = Get.put(ServerModel(WeakReference(this)));
  }

  updateEventListener(UuidValue sessionID, String peerId) {
    platformFFi.setEventCallback(startEventListener(sessionID, peerId));
  }

  StreamEventHandler startEventListener(UuidValue sessionID, String peerId) {
    return (event) async {
      String name = event['name'];
      switch (name) {
        case "add_connection":
          serverModel.addConnection(event);
          break;
        case "on_client_remove":
          serverModel.onClientRemove(event);
          break;
        case "show_elevation":
          final show = event['show'].toString() == 'true';
          serverModel.showElevation(show);
          break;
        case "update_voice_call_state":
          serverModel.updateVoiceCallState(event);
          break;
        default:
          debugPrint(
            'unhandled event $sessionID $peerId $name $event',
          );
      }
    };
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<StateModel>();
    Get.delete<ServerModel>();
    Get.delete<PlatformFFi>();
  }
}
