import 'dart:async';

import 'package:bluez/src/bluez_peripheral_gatt_application.dart';
import 'package:dbus/dbus.dart';
import 'bluez_client.dart';
import 'bluez_object.dart';
import 'bluez_peripheral_gatt_characteristic.dart';
import 'bluez_peripheral_gatt_service.dart';

class BlueZPeripheralGattServiceDescription {
  final String uuid;
  final bool primary;
  final List<BlueZPeripheralGattCharacteristicDescription> characteristics;

  BlueZPeripheralGattServiceDescription({
    required this.uuid,
    this.primary = true,
    required this.characteristics,
  });
}

class BlueZPeripheralGattCharacteristicDescription {
  final String uuid;
  final List<String> flags;

  BlueZPeripheralGattCharacteristicDescription({
    required this.uuid,
    required this.flags,
  });
}

class BlueZGattData {
  String uuid;
  List<int> data;

  BlueZGattData(this.uuid, this.data);
}

class BlueZGATTManager {
  final BlueZClient _client;
  final BlueZObject _object;

  BlueZGATTManager(this._client, this._object);

  BlueZPeripheralGattApplication? application;
  final Map<String, BlueZPeripheralGattCharacteristic> _characteristics = {};

  final StreamController<BlueZGattData> _dataReceivedCtrl = StreamController.broadcast();
  Stream<BlueZGattData> get dataStream => _dataReceivedCtrl.stream;

  Future<void> registerApplicationWithServices(List<BlueZPeripheralGattServiceDescription> serviceDescriptions,
      {Map<String, DBusValue> options = const {}}) async {
    print('client ${_client}');
    print('object ${_object.path}');

    DBusObjectPath appPath = _object.path;

    // Build service/characteristics tree
    List<BlueZPeripheralGattService> services = [];
    for (int s = 0; s < serviceDescriptions.length; s++) {
      BlueZPeripheralGattServiceDescription serviceDescription = serviceDescriptions[s];
      DBusObjectPath servicePath = DBusObjectPath('${appPath.value}/service$s');

      List<BlueZPeripheralGattCharacteristic> characteristics = [];
      for (int p = 0; p < serviceDescription.characteristics.length; p++) {
        BlueZPeripheralGattCharacteristicDescription characteristicDescription = serviceDescription.characteristics[p];
        DBusObjectPath characteristicPath = DBusObjectPath('${servicePath.value}/char$s');

        BlueZPeripheralGattCharacteristic characteristic = BlueZPeripheralGattCharacteristic(
          characteristicPath,
          uuid: characteristicDescription.uuid,
          flags: characteristicDescription.flags,
          servicePath: servicePath,
          onWrite: (data) {
            _handleDataFromCharacteristic(characteristicDescription.uuid, data);
          },
          onStartNotify: () {
            print('StartNotify');
          },
          onStopNotify: () {
            print('StopNotify');
          },
        );

        characteristics.add(characteristic);
        _characteristics[characteristicDescription.uuid] = characteristic;
      }

      // Set up service
      BlueZPeripheralGattService service = BlueZPeripheralGattService(
        servicePath,
        uuid: serviceDescription.uuid,
        primary: serviceDescription.primary,
        characteristics: characteristics,
      );
      services.add(service);
    }

    application = BlueZPeripheralGattApplication(appPath, services);

    // Register
    print('register app ${appPath.value}');
    await _client.registerObject(application!);

    for (var service in services) {
      print('register service ${service.path.value}');
      await _client.registerObject(service);

      // And its characteristics
      for (var characteristic in service.characteristics) {
        print('register characteristic ${characteristic.path.value}');
        await _client.registerObject(characteristic);

        for (var descriptor in characteristic.descriptors) {
          print('register descriptor ${descriptor.path.value}');
          await _client.registerObject(descriptor);
        }
      }
    }

    await _object.callMethod(
      'org.bluez.GattManager1',
      'RegisterApplication',
      [appPath, DBusDict.stringVariant(options)],
    );
  }

  Future<void> unregisterApplication() async {
    await _object.callMethod(
      'org.bluez.GattManager1',
      'UnregisterApplication',
      [_object.path],
    );

    _characteristics.clear();
  }

  void _handleDataFromCharacteristic(String uuid, List<int> data) {
    _dataReceivedCtrl.add(BlueZGattData(uuid, data));
  }

  void sendDataToCharacteristic(String uuid, List<int> data) {
    var characteristic = _characteristics[uuid];
    if (characteristic != null) {
      characteristic.setValue(data);
    } else {
      print('Characteristic not found: $uuid');
    }
  }
}
