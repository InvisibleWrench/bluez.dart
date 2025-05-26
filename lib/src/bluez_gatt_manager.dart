import 'package:bluez/src/bluez_peripheral_gatt_application.dart';
import 'package:dbus/dbus.dart';
import 'bluez_client.dart';
import 'bluez_object.dart';
import 'bluez_peripheral_gatt_characteristic.dart';
import 'bluez_peripheral_gatt_service.dart';

class BlueZGATTManager {
  final BlueZClient _client;
  final BlueZObject _object;

  BlueZGATTManager(this._client, this._object);

  BlueZPeripheralGattApplication? application;

  Future<void> registerApplication(BlueZPeripheralGattApplication app, {Map<String, DBusValue> options = const {}}) async {
    print("client ${_client}");
    print("object ${_object.path}");

    print("register app ${app.path}");

    application = app;

    await _client.registerObject(app);

    for (BlueZPeripheralGattService service in app.services) {
      print('register service $service ${service.path.value}');
      await _client.registerObject(service);

      for (BlueZPeripheralGattCharacteristic characteristic in service.characteristics) {
        print('register characteristic $characteristic ${characteristic.path.value}');
        await _client.registerObject(characteristic);
      }
    }

    await Future.delayed(Duration(milliseconds: 500));

    await _object.callMethod(
      'org.bluez.GattManager1',
      'RegisterApplication',
      [app.path, DBusDict.stringVariant(options)],
    );
  }

  Future<void> unregisterApplication(BlueZPeripheralGattApplication app) async {
    await _object.callMethod(
      'org.bluez.GattManager1',
      'UnregisterApplication',
      [app.path],
    );
  }
}
