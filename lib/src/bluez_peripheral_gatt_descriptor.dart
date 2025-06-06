import 'package:dbus/dbus.dart';

class BlueZPeripheralGattDescriptor extends DBusObject {
  final String uuid;
  final DBusObjectPath characteristicPath;

  List<int> _value = [0x00, 0x00]; // Default: notifications disabled

  final void Function(List<int>)? onWrite;

  BlueZPeripheralGattDescriptor(
    DBusObjectPath path, {
    required this.uuid,
    required this.characteristicPath,
    this.onWrite,
  }) : super(path);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.GattDescriptor1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'ReadValue':
        return DBusMethodSuccessResponse([
          DBusArray.byte(_value),
        ]);

      case 'WriteValue':
        final data = methodCall.values[0].asByteArray().toList();
        _value = data;
        onWrite?.call(data);
        return DBusMethodSuccessResponse();

      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != 'org.bluez.GattDescriptor1') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (name) {
      case 'UUID':
        return DBusGetPropertyResponse(DBusString(uuid));
      case 'Characteristic':
        return DBusGetPropertyResponse(characteristicPath);
      case 'Value':
        return DBusGetPropertyResponse(DBusArray.byte(_value));
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != 'org.bluez.GattDescriptor1') {
      return DBusGetAllPropertiesResponse({});
    }

    return DBusGetAllPropertiesResponse({
      'UUID': DBusString(uuid),
      'Characteristic': characteristicPath,
      'Value': DBusArray.byte(_value),
    });
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        'org.bluez.GattDescriptor1',
        methods: [
          DBusIntrospectMethod(
            'ReadValue',
            args: [
              DBusIntrospectArgument(DBusSignature('a{sv}'), DBusArgumentDirection.in_, name: 'options'),
              DBusIntrospectArgument(DBusSignature('ay'), DBusArgumentDirection.out, name: 'value'),
            ],
          ),
          DBusIntrospectMethod(
            'WriteValue',
            args: [
              DBusIntrospectArgument(DBusSignature('ay'), DBusArgumentDirection.in_, name: 'value'),
              DBusIntrospectArgument(DBusSignature('a{sv}'), DBusArgumentDirection.in_, name: 'options'),
            ],
          ),
        ],
        properties: [
          DBusIntrospectProperty('UUID', DBusSignature('s'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Characteristic', DBusSignature('o'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Value', DBusSignature('ay'), access: DBusPropertyAccess.read),
        ],
      ),
    ];
  }
}
