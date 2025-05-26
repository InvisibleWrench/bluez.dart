import 'package:bluez/src/bluez_peripheral_gatt_characteristic.dart';
import 'package:dbus/dbus.dart';



class BlueZPeripheralGattService extends DBusObject {
  final String uuid;
  final bool primary;
  final List<BlueZPeripheralGattCharacteristic> characteristics;

  BlueZPeripheralGattService(
      DBusObjectPath path, {
        required this.uuid,
        this.primary = true,
        required this.characteristics,
      }) : super(path);

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != 'org.bluez.GattService1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (name) {
      case 'UUID':
        return DBusGetPropertyResponse(DBusString(uuid));
      case 'Primary':
        return DBusGetPropertyResponse(DBusBoolean(primary));
      case 'Characteristics':
        return DBusGetPropertyResponse(DBusArray.objectPath(
            characteristics.map((c) => c.path).toList()));
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != 'org.bluez.GattService1') {
      return DBusGetAllPropertiesResponse({});
    }

    return DBusGetAllPropertiesResponse({
      'UUID': DBusString(uuid),
      'Primary': DBusBoolean(primary),
      'Characteristics':
      DBusArray.objectPath(characteristics.map((c) => c.path).toList()),
    });
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        'org.bluez.GattService1',
        methods: [],
        properties: [
          DBusIntrospectProperty('UUID', DBusSignature('s'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Primary', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Characteristics', DBusSignature('ao'),
              access: DBusPropertyAccess.read),
        ],
      ),
    ];
  }

  Future<Map<String, Map<String, DBusValue>>> getDBusProperties() async {
    return {
      'org.bluez.GattService1': {
        'UUID': DBusString(uuid),
        'Primary': DBusBoolean(primary),
        'Characteristics': DBusArray.objectPath(
          characteristics.map((c) => c.path).toList(),
        ),
      },
    };
  }
}
