import 'package:dbus/dbus.dart';
import 'bluez_peripheral_gatt_service.dart';

class BlueZPeripheralGattApplication extends DBusObject {
  final List<BlueZPeripheralGattService> services;

  BlueZPeripheralGattApplication(DBusObjectPath path, this.services) : super(path);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.freedesktop.DBus.ObjectManager' && methodCall.name == 'GetManagedObjects') {
      // Construct the managed objects dictionary
      final Map<DBusValue, DBusValue> managedObjects = {};

      for (final service in services) {
        // Service properties dict (a{sv})
        final serviceProps = <DBusValue, DBusValue>{
          DBusString('UUID'): DBusVariant(DBusString(service.uuid)),
          DBusString('Primary'): DBusVariant(DBusBoolean(service.primary)),
          DBusString('Characteristics'): DBusVariant(DBusArray.objectPath(
            service.characteristics.map((c) => c.path).toList(),
          )),
        };

        // Service interface dict (a{sa{sv}})
        final serviceInterfaces = <DBusValue, DBusValue>{
          DBusString('org.bluez.GattService1'): DBusDict(
            DBusSignature('s'),
            DBusSignature('v'),
            serviceProps,
          ),
        };

        managedObjects[service.path] = DBusDict(
          DBusSignature('s'),
          DBusSignature('a{sv}'),
          serviceInterfaces,
        );

        for (final characteristic in service.characteristics) {
          final charProps = <DBusValue, DBusValue>{
            DBusString('UUID'): DBusVariant(DBusString(characteristic.uuid)),
            DBusString('Flags'): DBusVariant(DBusArray.string(characteristic.flags)),
            DBusString('Value'): DBusVariant(DBusArray.byte(characteristic.value)),
            DBusString('Service'): DBusVariant(characteristic.servicePath),
          };

          final charInterfaces = <DBusValue, DBusValue>{
            DBusString('org.bluez.GattCharacteristic1'): DBusDict(
              DBusSignature('s'),
              DBusSignature('v'),
              charProps,
            ),
          };

          managedObjects[characteristic.path] = DBusDict(
            DBusSignature('s'),
            DBusSignature('a{sv}'),
            charInterfaces,
          );
        }
      }

      final response = DBusDict(
        DBusSignature('o'),
        DBusSignature('a{sa{sv}}'),
        managedObjects,
      );

      return DBusMethodSuccessResponse([response]);
    }

    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        'org.freedesktop.DBus.ObjectManager',
        methods: [
          DBusIntrospectMethod(
            'GetManagedObjects',
            args: [
              DBusIntrospectArgument(DBusSignature('a{oa{sa{sv}}}'), DBusArgumentDirection.out, name: 'objects'),
            ],
          ),
        ],
      ),
    ];
  }
}
