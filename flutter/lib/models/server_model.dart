import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/ffi_model.dart';
import 'package:flutter_hbb/models/client_model.dart';

enum ServerVerificationMethod {
  permanentPassword("use-permanent-password");

  final String value;
  const ServerVerificationMethod(this.value);
}

enum ConnectionStatus {
  connecting,
  pending,
  ready,
}

enum ApproveMode {
  click("click"),
  password("password");

  final String value;
  const ApproveMode(this.value);
}

class ServerModel extends GetxController {
  late Timer scheduler;
  final WeakReference<FFIModel> parent;

  final RxString serverId = "".obs;
  final RxBool fileOk = false.obs;
  final RxBool mediaOk = false.obs;
  final RxBool inputOk = false.obs;
  final RxBool audioOk = false.obs;
  final RxBool hideCm = false.obs;
  final RxBool isStarted = false.obs;
  final RxBool clipboardOk = false.obs;
  final RxBool showElevation = false.obs;
  final RxInt zeroClientLengthCount = 0.obs;
  final Rx<ServerVerificationMethod> verificationMethod =
      ServerVerificationMethod.permanentPassword.obs;
  final Rx<ConnectionStatus> connectStatus = ConnectionStatus.pending.obs;

  final RxList<Client> clients = RxList([]);

  ServerModel(this.parent) {
    Future.delayed(Duration.zero, () async {
      if (await bind.optionSynced()) {
        await _updateStatus();
      }
    });

    scheduler = Timer.periodic(Duration(seconds: 1), (timer) async {
      await _updateStatus();
    });
  }

  Future<void> _updateStatus() async {
    final connectionStatus =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final connectingStatus = connectionStatus['status_num'] as int;
    if (connectingStatus > 0) {
      connectStatus.value = ConnectionStatus.ready;
    } else if (connectingStatus < 0) {
      connectStatus.value = ConnectionStatus.pending;
    } else {
      connectStatus.value = ConnectionStatus.connecting;
    }

    serverId.value = await bind.mainGetMyId();
    if (parent.target?.stateModel.desktopType.value == DesktopType.cm) {
      final response = await bind.cmCheckClientsLength(length: clients.length);
      if (response != null) {
        updateClientState(response);
      }
    }

    await updateClientState();
  }

  @override
  void dispose() {
    super.dispose();
    scheduler.cancel();
  }

  Future<void> setVerificationMethod(ServerVerificationMethod method) async {
    return await bind.mainSetOption(
        key: GlobalOptions.verificationMethod.value, value: method.value);
  }

  Future<void> setApproveMode(String mode) async {
    return await bind.mainSetOption(
        key: GlobalOptions.approveMode.value, value: mode);
  }

  Future<void> closeAll() async {
    await Future.wait(
        clients.map((client) => bind.cmCloseConnection(connId: client.id)));
    clients.clear();
  }

  Future<void> updateClientState([String? json]) async {
    var response = await bind.cmGetClientsState();
    List<dynamic> clientsJson = jsonDecode(response);
    clients.clear();
    for (var clientJson in clientsJson) {
      final client = Client.fromJson(clientJson);
      clients.add(client);
      _sendLoginResponse(client, true);
    }
  }

  Future<void> startService() async {
    isStarted.value = true;
    parent.target?.updateEventListener(parent.target!.sessionId, '');

    await bind.mainStartService();
    updateClientState();
  }

  Future<void> _sendLoginResponse(Client client, bool response) async {
    await bind.cmLoginRes(connId: client.id, res: response);

    if (response) {
      client.authorized = true;
    } else {
      clients.remove(client);
    }
  }

  Future<void> addConnection(Map<String, dynamic> event) async {
    final client = Client.fromJson(jsonDecode(event['client']));
    if (client.authorized) {
      final index = clients.indexWhere((element) => element.id == client.id);
      if (index < 0) {
        clients.add(client);
      } else {
        clients[index].authorized = true;
      }
    } else {
      if (clients.any((element) => element.id == client.id)) {
        return;
      }

      await _sendLoginResponse(client, true);

      final indexDisconnected = clients.indexWhere(
          (element) => element.disconnected && element.peerId == client.peerId);
      if (indexDisconnected >= 0) {
        clients.removeAt(indexDisconnected);
      }
    }
  }

  void onClientRemove(Map<String, dynamic> event) {
    final id = int.parse(event['id'] as String);
    final close = event['close'] as String == 'true';
    final index = clients.indexWhere((client) => client.id == id);
    if (index != -1) {
      if (close) {
        clients.removeAt(index);
      } else {
        clients[index].disconnected = true;
      }
    }
  }

  void updateVoiceCallState(Map<String, dynamic> event) {
    final client = Client.fromJson(event);
    final index = clients.indexWhere((element) => element.id == client.id);
    if (index != -1) {
      clients[index].inVoiceCall = client.inVoiceCall;
      clients[index].incomingVoiceCall = client.incomingVoiceCall;
    }
  }

  void setShowElevation(bool show) {
    showElevation.value = show;
  }
}
