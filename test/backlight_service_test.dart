import 'dart:io';

import 'package:brightness_flutter/backlight_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backlight-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('loads backlight devices from sysfs-style directories', () async {
    await _writeDevice(
      root,
      'intel_backlight',
      brightness: 200,
      maxBrightness: 1000,
      actualBrightness: 180,
      type: 'raw',
    );
    await _writeDevice(root, 'acpi_video0', brightness: 4, maxBrightness: 10);

    final devices = await SysfsBacklightService(root: root).loadDevices();

    expect(devices.map((device) => device.name), [
      'acpi_video0',
      'intel_backlight',
    ]);
    expect(devices.last.brightness, 200);
    expect(devices.last.maxBrightness, 1000);
    expect(devices.last.actualBrightness, 180);
    expect(devices.last.type, 'raw');
  });

  test('writes clamped brightness to a device', () async {
    final directory = await _writeDevice(
      root,
      'panel0',
      brightness: 5,
      maxBrightness: 10,
    );
    final device = BacklightDevice(
      name: 'panel0',
      path: directory.path,
      brightness: 5,
      maxBrightness: 10,
    );

    final updated = await SysfsBacklightService(
      root: root,
    ).setBrightness(device, 99);

    expect(updated.brightness, 10);
    expect(await File('${directory.path}/brightness').readAsString(), '10\n');
  });
}

Future<Directory> _writeDevice(
  Directory root,
  String name, {
  required int brightness,
  required int maxBrightness,
  int? actualBrightness,
  String? type,
}) async {
  final directory = Directory('${root.path}/$name');
  await directory.create();
  await File('${directory.path}/brightness').writeAsString('$brightness\n');
  await File(
    '${directory.path}/max_brightness',
  ).writeAsString('$maxBrightness\n');
  if (actualBrightness != null) {
    await File(
      '${directory.path}/actual_brightness',
    ).writeAsString('$actualBrightness\n');
  }
  if (type != null) {
    await File('${directory.path}/type').writeAsString('$type\n');
  }
  return directory;
}
