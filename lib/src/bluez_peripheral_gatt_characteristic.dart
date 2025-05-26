import 'package:dbus/dbus.dart';

class BlueZPeripheralGattCharacteristic extends DBusObject {
  final String uuid;
  final List<String> flags;
  final DBusObjectPath servicePath;

  List<int> _value = [];
  bool _notifying = false;

  final void Function(List<int>)? onWrite;
  final void Function()? onStartNotify;
  final void Function()? onStopNotify;

  List<int> get value => _value;

  BlueZPeripheralGattCharacteristic(
      DBusObjectPath path, {
        required this.uuid,
        required this.flags,
        required this.servicePath,
        this.onWrite,
        this.onStartNotify,
        this.onStopNotify,
      }) : super(path);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.GattCharacteristic1') {
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

      case 'StartNotify':
        _notifying = true;
        onStartNotify?.call();
        return DBusMethodSuccessResponse();

      case 'StopNotify':
        _notifying = false;
        onStopNotify?.call();
        return DBusMethodSuccessResponse();

      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != 'org.bluez.GattCharacteristic1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (name) {
      case 'UUID':
        return DBusGetPropertyResponse(DBusString(uuid));
      case 'Service':
        return DBusGetPropertyResponse(servicePath);
      case 'Flags':
        return DBusGetPropertyResponse(DBusArray.string(flags));
      case 'Value':
        return DBusGetPropertyResponse(DBusArray.byte(_value));
      case 'Notifying':
        return DBusGetPropertyResponse(DBusBoolean(_notifying));
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != 'org.bluez.GattCharacteristic1') {
      return DBusGetAllPropertiesResponse({});
    }

    return DBusGetAllPropertiesResponse({
      'UUID': DBusString(uuid),
      'Service': servicePath,
      'Flags': DBusArray.string(flags),
      'Value': DBusArray.byte(_value),
      'Notifying': DBusBoolean(_notifying),
    });
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        'org.bluez.GattCharacteristic1',
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
          DBusIntrospectMethod('StartNotify'),
          DBusIntrospectMethod('StopNotify'),
        ],
        properties: [
          DBusIntrospectProperty('UUID', DBusSignature('s'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Service', DBusSignature('o'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Flags', DBusSignature('as'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Value', DBusSignature('ay'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Notifying', DBusSignature('b'), access: DBusPropertyAccess.read),
        ],
      ),
    ];
  }

  // Send a notification
  Future<void> notify(DBusClient client, List<int> data) async {
    _value = data;
    if (!_notifying) return;
    await client.emitSignal(
      path: path,
      interface: 'org.freedesktop.DBus.Properties',
      name: 'PropertiesChanged',
      values: [
        DBusString('org.bluez.GattCharacteristic1'),
        DBusDict.stringVariant({
          'Value': DBusVariant(DBusArray.byte(_value)),
        }),
        DBusArray.string([]),
      ],
    );
  }

  Future<Map<String, Map<String, DBusValue>>> getDBusProperties() async {
    return {
      'org.bluez.GattCharacteristic1': {
        'UUID': DBusString(uuid),
        'Service': servicePath,
        'Flags': DBusArray.string(flags),
        'Value': DBusArray.byte(_value),
        'Notifying': DBusBoolean(_notifying),
      },
    };
  }
}
