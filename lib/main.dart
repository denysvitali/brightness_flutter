import 'dart:io';

import 'package:flutter/material.dart';

import 'backlight_service.dart';

void main() {
  runApp(const BrightnessApp());
}

class BrightnessApp extends StatelessWidget {
  const BrightnessApp({super.key, this.service});

  final BacklightService? service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brightness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0f766e),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff14b8a6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: BrightnessHome(service: service ?? SysfsBacklightService()),
    );
  }
}

class BrightnessHome extends StatefulWidget {
  const BrightnessHome({super.key, required this.service});

  final BacklightService service;

  @override
  State<BrightnessHome> createState() => _BrightnessHomeState();
}

class _BrightnessHomeState extends State<BrightnessHome> {
  var _devices = <BacklightDevice>[];
  final _busyDevices = <String>{};
  final _deviceErrors = <String, String>{};
  Object? _loadError;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _deviceErrors.clear();
    });

    try {
      final devices = await widget.service.loadDevices();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _setBrightness(BacklightDevice device, double value) async {
    final brightness = value.round().clamp(0, device.maxBrightness);
    _updateDevice(device.copyWith(brightness: brightness));

    setState(() {
      _busyDevices.add(device.path);
      _deviceErrors.remove(device.path);
    });

    try {
      final updated = await widget.service.setBrightness(device, brightness);
      if (!mounted) {
        return;
      }
      _updateDevice(updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceErrors[device.path] = _formatWriteError(error);
      });
      _showError(_formatWriteError(error));
      await _loadDevices();
    } finally {
      if (mounted) {
        setState(() {
          _busyDevices.remove(device.path);
        });
      }
    }
  }

  void _updateDevice(BacklightDevice updated) {
    setState(() {
      _devices = [
        for (final device in _devices)
          if (device.path == updated.path) updated else device,
      ];
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatWriteError(Object error) {
    if (error is FileSystemException) {
      return 'Could not write brightness. Check root or udev permissions.';
    }
    return 'Could not update brightness.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brightness'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadDevices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildBody(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return _MessagePanel(
        icon: Icons.error_outline,
        title: 'Backlight scan failed',
        message: 'Could not read /sys/class/backlight.',
        action: FilledButton.icon(
          onPressed: _loadDevices,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }

    if (_devices.isEmpty) {
      return _MessagePanel(
        icon: Icons.light_mode_outlined,
        title: 'No backlights found',
        message: 'No devices were found under /sys/class/backlight.',
        action: FilledButton.icon(
          onPressed: _loadDevices,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );
    }

    return ListView.separated(
      itemCount: _devices.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final device = _devices[index];
        return _BacklightCard(
          device: device,
          busy: _busyDevices.contains(device.path),
          error: _deviceErrors[device.path],
          onChanged: (value) =>
              _updateDevice(device.copyWith(brightness: value.round())),
          onChangeEnd: (value) => _setBrightness(device, value),
        );
      },
    );
  }
}

class _BacklightCard extends StatelessWidget {
  const _BacklightCard({
    required this.device,
    required this.busy,
    required this.onChanged,
    required this.onChangeEnd,
    this.error,
  });

  final BacklightDevice device;
  final bool busy;
  final String? error;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = device.percent.round();
    final actual = device.actualBrightness;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name, style: theme.textTheme.titleLarge),
                      Text(
                        device.type == null
                            ? device.path
                            : '${device.type} • ${device.path}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text('$percent%', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 18),
            Slider(
              min: 0,
              max: device.maxBrightness.toDouble(),
              divisions: device.maxBrightness <= 1000
                  ? device.maxBrightness
                  : null,
              value: device.brightness
                  .clamp(0, device.maxBrightness)
                  .toDouble(),
              label: '$percent%',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${device.brightness} / ${device.maxBrightness}'),
                if (actual != null) ...[
                  const SizedBox(width: 12),
                  Text('actual $actual'),
                ],
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
