import 'package:bluez/src/bluez_peripheral_gatt_descriptor.dart';
import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';

final _log = Logger('bluez.gatt');

class BlueZPeripheralGattCharacteristic extends DBusObject {
  final String uuid;
  final List<String> flags;
  final DBusObjectPath servicePath;
  final List<BlueZPeripheralGattDescriptor> descriptors = [];
  final int mtu;
  List<int> _value = [];
  var _notifying = false;

  /// Called on each write from a central. [device] is the D-Bus object path
  /// of the writing central (from the WriteValue options), null if absent.
  final void Function(List<int> value, String? device)? onWrite;
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
    this.mtu = 0,
  }) : super(path) {
    final cccd = BlueZPeripheralGattDescriptor(
      DBusObjectPath('${path.value}/desc0'),
      uuid: '00002902-0000-1000-8000-00805f9b34fb', // 0x2902
      characteristicPath: path,
      onWrite: (data) {
        if (data.length < 2) {
          _log.warning('CCCD write of ${data.length} byte(s) on $uuid, ignored');
          return;
        }
        int v = data[0] | (data[1] << 8);
        if (v == 0x0001) {
          _log.fine('CCCD on $uuid: notifications enabled');
          _notifying = true;
          onStartNotify?.call();
        } else if (v == 0x0002) {
          _log.fine('CCCD on $uuid: indications enabled');
          _notifying = true;
          onStartNotify?.call();
        } else if (v == 0x0000) {
          _log.fine('CCCD on $uuid: notifications disabled');
          _notifying = false;
          onStopNotify?.call();
        } else {
          _log.warning('CCCD on $uuid: unknown value $data');
        }
      },
    );

    descriptors.add(cccd);
  }

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
        String? device;
        if (methodCall.values.length > 1) {
          final options = methodCall.values[1].asStringVariantDict();
          final deviceOption = options['device'];
          if (deviceOption is DBusObjectPath) {
            device = deviceOption.value;
          }
        }
        _value = data;
        onWrite?.call(data, device);
        return DBusMethodSuccessResponse();
      case 'AcquireWrite':
      case 'AcquireNotify':
        // Not supported: the socket-based acquire paths cannot attribute
        // writes to a central and are not advertised (no WriteAcquired /
        // NotifyAcquired properties), so bluetoothd uses WriteValue /
        // StartNotify instead.
        return DBusMethodErrorResponse('org.bluez.Error.NotSupported');
      case 'StartNotify':
        if (_notifying) {
          return DBusMethodErrorResponse('org.bluez.Error.InProgress');
        }
        await changeProperties(notifying: true);
        return DBusMethodSuccessResponse();
      case 'StopNotify':
        if (!_notifying) {
          return DBusMethodSuccessResponse();
        }
        await changeProperties(notifying: false);
        return DBusMethodSuccessResponse();
      case 'MTU':
        return DBusMethodSuccessResponse([DBusUint16(mtu)]);
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

  Future<void> changeProperties({bool? notifying, List<int>? value}) async {
    var changedProperties = <String, DBusValue>{};
    if (notifying != null) {
      _notifying = notifying;
      changedProperties['Notifying'] = DBusBoolean(notifying);
    }
    if (value != null) {
      _value = value;
      changedProperties['Value'] = DBusArray.byte(value);
    }
    await emitPropertiesChanged('org.bluez.GattCharacteristic1', changedProperties: changedProperties);
  }

  Future<void> setValue(List<int> value) async {
    if (_notifying) {
      await changeProperties(value: value);
    } else {
      _value = value;
    }
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
