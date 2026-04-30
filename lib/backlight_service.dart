import 'dart:io';

class BacklightDevice {
  const BacklightDevice({
    required this.name,
    required this.path,
    required this.brightness,
    required this.maxBrightness,
    this.actualBrightness,
    this.type,
    this.usesRoot = false,
    this.rootAvailable = false,
  });

  final String name;
  final String path;
  final int brightness;
  final int maxBrightness;
  final int? actualBrightness;
  final String? type;
  final bool usesRoot;
  final bool rootAvailable;

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
    bool? usesRoot,
    bool? rootAvailable,
  }) {
    return BacklightDevice(
      name: name,
      path: path,
      brightness: brightness ?? this.brightness,
      maxBrightness: maxBrightness ?? this.maxBrightness,
      actualBrightness: actualBrightness ?? this.actualBrightness,
      type: type ?? this.type,
      usesRoot: usesRoot ?? this.usesRoot,
      rootAvailable: rootAvailable ?? this.rootAvailable,
    );
  }
}

abstract class BacklightService {
  Future<List<BacklightDevice>> loadDevices();

  Future<BacklightDevice> setBrightness(BacklightDevice device, int brightness);
}

class BacklightAccessException implements Exception {
  const BacklightAccessException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class HybridBacklightService implements BacklightService {
  HybridBacklightService({
    SysfsBacklightService? direct,
    LedsBacklightService? leds,
    RootBacklightService? root,
    bool? rootFallbackEnabled,
  }) : direct = direct ?? SysfsBacklightService(),
       leds = leds ?? LedsBacklightService(),
       root = root ?? RootBacklightService(),
       rootFallbackEnabled = rootFallbackEnabled ?? Platform.isAndroid;

  final SysfsBacklightService direct;
  final LedsBacklightService leds;
  final RootBacklightService root;
  final bool rootFallbackEnabled;

  Future<bool> isRootAvailable() async {
    return await root.isRootAvailable();
  }

  Future<bool> loadDevicesWithRoot() async {
    try {
      final devices = await root.loadDevices();
      if (devices.isNotEmpty) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<List<BacklightDevice>> loadDevices() async {
    // Try direct backlight path first
    try {
      final devices = await direct.loadDevices();
      if (devices.isNotEmpty) {
        return devices;
      }
    } catch (_) {}

    // Try LEDs path
    try {
      final ledsDevices = await leds.loadDevices();
      if (ledsDevices.isNotEmpty) {
        return ledsDevices;
      }
    } catch (_) {}

    // If nothing found and root fallback disabled, return empty
    if (!rootFallbackEnabled) {
      return [];
    }

    // Try root fallback
    try {
      return await root.loadDevices();
    } catch (error) {
      throw BacklightAccessException(
        'Could not read backlight or LED devices. '
        'Root may be required on Android.',
        error,
      );
    }
  }

  @override
  Future<BacklightDevice> setBrightness(
    BacklightDevice device,
    int brightness,
  ) {
    if (device.usesRoot) {
      return root.setBrightness(device, brightness);
    }
    // Use LEDs service if device is from LEDs
    if (device.path.startsWith('/sys/class/leds')) {
      return leds.setBrightness(device, brightness);
    }
    return direct.setBrightness(device, brightness);
  }
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

class LedsBacklightService implements BacklightService {
  LedsBacklightService({Directory? root})
    : root = root ?? Directory('/sys/class/leds');

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
      // LED brightness files
      final brightness = await _readInt(directory, 'brightness');
      final maxBrightness = await _readInt(directory, 'max_brightness');

      // Only include devices that have valid brightness values
      if (brightness == null || maxBrightness == null || maxBrightness <= 0) {
        continue;
      }

      // Try to read actual_brightness if available
      final actualBrightness = await _readInt(directory, 'actual_brightness');

      // Get the LED type from subsystem link if available
      String? type;
      try {
        final link = Link(entity.path);
        if (await link.exists()) {
          final target = await link.target();
          // Extract subsystem from path like /sys/class/leds/backlight
          if (target.contains('leds')) {
            type = 'led';
          }
        }
      } catch (_) {}

      devices.add(
        BacklightDevice(
          name: entity.uri.pathSegments.where((part) => part.isNotEmpty).last,
          path: entity.path,
          brightness: brightness.clamp(0, maxBrightness),
          maxBrightness: maxBrightness,
          actualBrightness: actualBrightness,
          type: type ?? 'led',
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

typedef SuCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class RootBacklightService implements BacklightService {
  RootBacklightService({this.runner});

  final SuCommandRunner? runner;

  static const _backlightPath = '/sys/class/backlight';
  static const _ledsPath = '/sys/class/leds';

  @override
  Future<List<BacklightDevice>> loadDevices() async {
    final devices = <BacklightDevice>[];

    // Try backlight path first
    devices.addAll(await _loadFromPath(_backlightPath, 'backlight'));

    // Also try LEDs path
    devices.addAll(await _loadFromPath(_ledsPath, 'led'));

    devices.sort((a, b) => a.name.compareTo(b.name));
    return devices;
  }

  Future<List<BacklightDevice>> _loadFromPath(String basePath, String type) async {
    final devices = <BacklightDevice>[];
    try {
      final names = await _listDeviceNames(basePath);

      for (final name in names) {
        final path = '$basePath/$name';
        final brightness = await _readInt(path, 'brightness');
        final maxBrightness = await _readInt(path, 'max_brightness');
        if (brightness == null || maxBrightness == null || maxBrightness <= 0) {
          continue;
        }

        devices.add(
          BacklightDevice(
            name: name,
            path: path,
            brightness: brightness.clamp(0, maxBrightness),
            maxBrightness: maxBrightness,
            actualBrightness: await _readInt(path, 'actual_brightness'),
            type: type,
            usesRoot: true,
          ),
        );
      }
    } catch (_) {
      // Silently ignore errors for individual paths
    }
    return devices;
  }

  @override
  Future<BacklightDevice> setBrightness(
    BacklightDevice device,
    int brightness,
  ) async {
    final clamped = brightness.clamp(0, device.maxBrightness);
    await _runSu(
      "printf '%s\\n' ${_shellQuote('$clamped')} > "
      '${_shellQuote('${device.path}/brightness')}',
    );
    return device.copyWith(
      brightness: clamped,
      actualBrightness: await _readInt(device.path, 'actual_brightness'),
      usesRoot: true,
    );
  }

  Future<List<String>> _listDeviceNames(String rootPath) async {
    final output = await _runSu(
      'for path in ${_shellQuote(rootPath)}/*; '
      'do [ -d "\$path" ] && basename "\$path"; done || true',
    );
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<int?> _readInt(String path, String name) async {
    final value = await _readString(path, name);
    return value == null ? null : int.tryParse(value);
  }

  Future<String?> _readString(String path, String name) async {
    final file = _shellQuote('$path/$name');
    final output = await _runSu('[ -f $file ] && cat $file || true');
    final value = output.trim();
    return value.isEmpty ? null : value;
  }

  Future<String> _runSu(String command) async {
    final result = await (runner ?? Process.run)('su', ['-c', command]);
    if (result.exitCode != 0) {
      final error = '${result.stderr}'.trim();
      throw BacklightAccessException(
        error.isEmpty ? 'su command failed.' : error,
      );
    }
    return '${result.stdout}';
  }

  Future<bool> isRootAvailable() async {
    try {
      final result = await (runner ?? Process.run)('su', ['-c', 'echo test']);
      return result.exitCode == 0 && '${result.stdout}'.trim() == 'test';
    } catch (_) {
      return false;
    }
  }
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
