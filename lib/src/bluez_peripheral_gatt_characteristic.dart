import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bluez/src/bluez_peripheral_gatt_descriptor.dart';
import 'package:dbus/dbus.dart';

class BlueZPeripheralGattCharacteristic extends DBusObject {
  final String uuid;
  final List<String> flags;
  final DBusObjectPath servicePath;
  final List<BlueZPeripheralGattDescriptor> descriptors = [];
  final int mtu;
  List<int> _value = [];
  var _notifyAcquired = false;
  var _notifying = false;
  var _writeAcquired = false;

  final void Function(List<int>)? onWrite;
  final void Function()? onStartNotify;
  final void Function()? onStopNotify;

  List<int> get value => _value;

  final _writtenDataCompleter = Completer<List<int>>();
  Future<List<int>> get writtenData => _writtenDataCompleter.future;
  RawSocket? notifySocket;

  BlueZPeripheralGattCharacteristic(
    DBusObjectPath path, {
    required this.uuid,
    required this.flags,
    required this.servicePath,
    this.onWrite,
    this.onStartNotify,
    this.onStopNotify,
    this.mtu = 23,
  }) : super(path) {
    final cccd = BlueZPeripheralGattDescriptor(
      DBusObjectPath('${path.value}/desc0'),
      uuid: '00002902-0000-1000-8000-00805f9b34fb', // 0x2902
      characteristicPath: path,
      onWrite: (data) {
        print("CCCD write $data");
        int v = data[0] | (data[1] << 8);
        if (v == 0x0001) {
          print('CCCD: Notifications enabled');
          _notifying = true;
          onStartNotify?.call();
        } else if (v == 0x0002) {
          print('CCCD: Indications enabled');
          _notifying = true;
          onStartNotify?.call();
        } else if (v == 0x0000) {
          print('CCCD: Notifications disabled');
          _notifying = false;
          onStopNotify?.call();
        } else {
          print('CCCD: Unknown value $data');
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
        _value = data;
        onWrite?.call(data);
        return DBusMethodSuccessResponse();
      case 'AcquireWrite':
        if (_writeAcquired) {
          return DBusMethodErrorResponse('org.bluez.Error.Failed');
        }
        await changeProperties(writeAcquired: true);
        var address = makeRandomUnixAddress();
        var serverSocket = await ServerSocket.bind(address, 0);
        RawSocket? socket;
        unawaited(serverSocket.first.then((childSocket) async {
          _writtenDataCompleter.complete(await childSocket.first);
          await childSocket.close();
          await serverSocket.close();
          await socket?.close();
        }));
        socket = await RawSocket.connect(address, 0);
        var handle = ResourceHandle.fromRawSocket(socket);
        return DBusMethodSuccessResponse([DBusUnixFd(handle), DBusUint16(mtu)]);
      case 'AcquireNotify':
        if (_notifyAcquired) {
          return DBusMethodErrorResponse('org.bluez.Error.Failed');
        }
        await changeProperties(notifyAcquired: true);
        var address = makeRandomUnixAddress();
        RawSocket? socket;
        var serverSocket = await RawServerSocket.bind(address, 0);
        unawaited(serverSocket.first.then((childSocket) {
          notifySocket = childSocket;
          childSocket.listen((event) {
            if (event == RawSocketEvent.closed) {
              childSocket.close();
              serverSocket.close();
              socket?.close();
            }
          });
        }));
        socket = await RawSocket.connect(address, 0);
        var handle = ResourceHandle.fromRawSocket(socket);
        return DBusMethodSuccessResponse([DBusUnixFd(handle), DBusUint16(mtu)]);
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

  Future<void> changeProperties({bool? notifyAcquired, bool? notifying, List<int>? value, bool? writeAcquired}) async {
    var changedProperties = <String, DBusValue>{};
    if (notifyAcquired != null) {
      _notifyAcquired = notifyAcquired;
      changedProperties['NotifyAcquired'] = DBusBoolean(notifyAcquired);
    }
    if (notifying != null) {
      _notifying = notifying;
      changedProperties['Notifying'] = DBusBoolean(notifying);
    }
    if (value != null) {
      _value = value;
      changedProperties['Value'] = DBusArray.byte(value);
    }
    if (writeAcquired != null) {
      _writeAcquired = writeAcquired;
      changedProperties['WriteAcquired'] = DBusBoolean(writeAcquired);
    }
    await emitPropertiesChanged('org.bluez.GattCharacteristic1', changedProperties: changedProperties);
  }

  Future<void> setValue(List<int> value) async {
    if (_notifying) {
      await changeProperties(value: value);
    } else if (notifySocket != null) {
      notifySocket!.write(value);
    } else {
      value = value;
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

  InternetAddress makeRandomUnixAddress() {
    var path = '@bluez-mortrix-';
    var r = Random();
    final randomChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (var i = 0; i < 8; i++) {
      path += randomChars[r.nextInt(randomChars.length)];
    }
    return InternetAddress(path, type: InternetAddressType.unix);
  }
}
