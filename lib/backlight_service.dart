import 'dart:io';

class BacklightDevice {
  const BacklightDevice({
    required this.name,
    required this.path,
    required this.brightness,
    required this.maxBrightness,
    this.actualBrightness,
    this.type,
  });

  final String name;
  final String path;
  final int brightness;
  final int maxBrightness;
  final int? actualBrightness;
  final String? type;

  double get percent {
    if (maxBrightness <= 0) {
      return 0;
    }
    return (brightness / maxBrightness).clamp(0, 1) * 100;
  }

  BacklightDevice copyWith({
    int? brightness,
    int? actualBrightness,
    int? maxBrightness,
    String? type,
  }) {
    return BacklightDevice(
      name: name,
      path: path,
      brightness: brightness ?? this.brightness,
      maxBrightness: maxBrightness ?? this.maxBrightness,
      actualBrightness: actualBrightness ?? this.actualBrightness,
      type: type ?? this.type,
    );
  }
}

abstract class BacklightService {
  Future<List<BacklightDevice>> loadDevices();

  Future<BacklightDevice> setBrightness(BacklightDevice device, int brightness);
}

class SysfsBacklightService implements BacklightService {
  SysfsBacklightService({Directory? root})
    : root = root ?? Directory('/sys/class/backlight');

  final Directory root;

  @override
  Future<List<BacklightDevice>> loadDevices() async {
    if (!await root.exists()) {
      return [];
    }

    final devices = <BacklightDevice>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory && entity is! Link) {
        continue;
      }

      final directory = Directory(entity.path);
      final brightness = await _readInt(directory, 'brightness');
      final maxBrightness = await _readInt(directory, 'max_brightness');
      if (brightness == null || maxBrightness == null || maxBrightness <= 0) {
        continue;
      }

      devices.add(
        BacklightDevice(
          name: entity.uri.pathSegments.where((part) => part.isNotEmpty).last,
          path: entity.path,
          brightness: brightness.clamp(0, maxBrightness),
          maxBrightness: maxBrightness,
          actualBrightness: await _readInt(directory, 'actual_brightness'),
          type: await _readString(directory, 'type'),
        ),
      );
    }

    devices.sort((a, b) => a.name.compareTo(b.name));
    return devices;
  }

  @override
  Future<BacklightDevice> setBrightness(
    BacklightDevice device,
    int brightness,
  ) async {
    final clamped = brightness.clamp(0, device.maxBrightness);
    final directory = Directory(device.path);
    final file = File('${directory.path}/brightness');
    await file.writeAsString('$clamped\n', flush: true);

    final actualBrightness = await _readInt(directory, 'actual_brightness');
    return device.copyWith(
      brightness: clamped,
      actualBrightness: actualBrightness,
    );
  }

  Future<int?> _readInt(Directory directory, String name) async {
    final value = await _readString(directory, name);
    return value == null ? null : int.tryParse(value);
  }

  Future<String?> _readString(Directory directory, String name) async {
    final file = File('${directory.path}/$name');
    if (!await file.exists()) {
      return null;
    }
    final value = await file.readAsString();
    return value.trim();
  }
}
