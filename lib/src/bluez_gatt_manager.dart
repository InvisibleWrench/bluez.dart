import 'dart:async';

import 'package:bluez/src/bluez_peripheral_gatt_application.dart';
import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';
import 'bluez_client.dart';
import 'bluez_object.dart';
import 'bluez_peripheral_gatt_characteristic.dart';
import 'bluez_peripheral_gatt_service.dart';

final _log = Logger('bluez.gatt');

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

  /// D-Bus object path of the central that wrote the data
  /// (e.g. /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX), null if unknown.
  final String? devicePath;

  BlueZGattData(this.uuid, this.data, {this.devicePath});

  /// MAC address of the writing central parsed from [devicePath], null if
  /// unknown.
  String? get deviceAddress {
    final path = devicePath;
    if (path == null) return null;
    final match = RegExp(r'dev_((?:[0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2})$').firstMatch(path);
    return match?.group(1)?.replaceAll('_', ':');
  }
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
    DBusObjectPath appPath = _object.path;

    // Build service/characteristics tree
    List<BlueZPeripheralGattService> services = [];
    for (int s = 0; s < serviceDescriptions.length; s++) {
      BlueZPeripheralGattServiceDescription serviceDescription = serviceDescriptions[s];
      DBusObjectPath servicePath = DBusObjectPath('${appPath.value}/service$s');

      List<BlueZPeripheralGattCharacteristic> characteristics = [];
      for (int p = 0; p < serviceDescription.characteristics.length; p++) {
        BlueZPeripheralGattCharacteristicDescription characteristicDescription = serviceDescription.characteristics[p];
        // Indexed by the characteristic, not by the service: with `$s` a
        // service's second characteristic got the same object path as its
        // first, and dbus replaces the object at a path it already holds
        // without complaining, so one of them silently vanished.
        DBusObjectPath characteristicPath = DBusObjectPath('${servicePath.value}/char$p');

        BlueZPeripheralGattCharacteristic characteristic = BlueZPeripheralGattCharacteristic(
          characteristicPath,
          uuid: characteristicDescription.uuid,
          flags: characteristicDescription.flags,
          servicePath: servicePath,
          onWrite: (data, device) {
            _handleDataFromCharacteristic(characteristicDescription.uuid, data, device);
          },
          onStartNotify: () {
            _log.fine('StartNotify on ${characteristicDescription.uuid}');
          },
          onStopNotify: () {
            _log.fine('StopNotify on ${characteristicDescription.uuid}');
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

    final app = BlueZPeripheralGattApplication(appPath, services);

    // All of it or none of it. A failure half way through used to leave objects
    // exported and `application` set, and since nothing unexported them, the
    // next attempt built a second set on the same paths - which dbus accepts
    // silently, orphaning the first. A caller retrying a failed enable is the
    // normal case, not an unusual one.
    try {
      _log.fine('register app ${appPath.value}');
      await _client.registerObject(app);

      for (var service in services) {
        _log.fine('register service ${service.path.value}');
        await _client.registerObject(service);

        // And its characteristics
        for (var characteristic in service.characteristics) {
          _log.fine('register characteristic ${characteristic.path.value}');
          await _client.registerObject(characteristic);

          for (var descriptor in characteristic.descriptors) {
            _log.fine('register descriptor ${descriptor.path.value}');
            await _client.registerObject(descriptor);
          }
        }
      }

      await _object.callMethod(
        'org.bluez.GattManager1',
        'RegisterApplication',
        [appPath, DBusDict.stringVariant(options)],
      );
    } catch (e) {
      _log.warning('registering the GATT application failed, undoing it', e);
      await _unregisterObjectsOf(app);
      _characteristics.clear();
      rethrow;
    }

    // Set last, so `application != null` means "bluetoothd has it": that is
    // what callers test before notifying on a characteristic.
    application = app;
  }

  /// Unexports an application's objects, in the reverse of the order they were
  /// registered. Best effort per object: this runs when something has already
  /// gone wrong, or when the application is already unregistered, and stopping
  /// half way because one object objected would leave the worse mess.
  Future<void> _unregisterObjectsOf(BlueZPeripheralGattApplication app) async {
    for (final service in app.services) {
      for (final characteristic in service.characteristics) {
        for (final descriptor in characteristic.descriptors) {
          await _unregister(descriptor, 'descriptor');
        }
        await _unregister(characteristic, 'characteristic');
      }
      await _unregister(service, 'service');
    }
    await _unregister(app, 'app');
  }

  /// Unregisters the application and the objects it exported.
  ///
  /// The order matters. This used to clear [_characteristics] first, so a bus
  /// call that failed left an application bluetoothd still had, that nothing
  /// here could notify on any more: [sendDataToCharacteristic] simply found no
  /// characteristic and returned. Now nothing is torn down until the call has
  /// returned, and a failure leaves the manager exactly as it was, so it can be
  /// tried again.
  Future<void> unregisterApplication() async {
    final app = application;
    // Not an error: a session that never advertised reaches here from both
    // `setAdvertisingEnabled(false)` and teardown.
    if (app == null) {
      _log.fine('no GATT application to unregister');
      return;
    }

    await _object.callMethod(
      'org.bluez.GattManager1',
      'UnregisterApplication',
      [_object.path],
    );

    // The exported objects go too. Without this they stayed on the bus and kept
    // their client, and registering again - which is what toggling advertising
    // does - built a second set on the same paths. dbus replaces the object at
    // a path it already holds silently, so the old tree was simply orphaned,
    // never announced as removed, and never collected.
    await _unregisterObjectsOf(app);

    _characteristics.clear();
    application = null;
  }

  Future<void> _unregister(DBusObject object, String what) async {
    try {
      await _client.unregisterObject(object);
    } catch (e) {
      _log.warning('could not unregister $what ${object.path.value}: $e');
    }
  }

  void _handleDataFromCharacteristic(String uuid, List<int> data, String? devicePath) {
    _dataReceivedCtrl.add(BlueZGattData(uuid, data, devicePath: devicePath));
  }

  /// Notifies subscribed centrals of a new value for [uuid].
  ///
  /// Returns a future that completes when the PropertiesChanged signal has gone
  /// out, and that *fails* when it could not. It used to be `void` with an
  /// un-awaited `setValue` inside it, so a failure landed on a future no caller
  /// could hold: an uncaught async error, which in a Flutter isolate is fatal.
  /// That is exactly how a mortrix unit lost its whole MIDI engine in the field
  /// — on the central role, through the same shape of call — and the peripheral
  /// role had it too until this returned a future.
  ///
  /// A write for a characteristic this application does not have is not a
  /// failure: a caller that sends to a UUID while the application is
  /// unregistered has nothing to do about it, and it was silent before.
  Future<void> sendDataToCharacteristic(String uuid, List<int> data) async {
    var characteristic = _characteristics[uuid];
    if (characteristic == null) return;
    await characteristic.setValue(data);
  }
}
