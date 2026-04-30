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
      home: BrightnessHome(service: service ?? HybridBacklightService()),
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
  var _rootChecked = false;
  var _rootAvailable = false;
  var _rootMode = false;

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
      final List<BacklightDevice> devices;
      if (_rootMode) {
        final hybrid = widget.service as HybridBacklightService;
        final ok = await hybrid.loadDevicesWithRoot();
        if (!ok) {
          throw const BacklightAccessException(
            'Root access failed. Could not read backlight devices.',
          );
        }
        devices = await hybrid.root.loadDevices();
      } else {
        devices = await widget.service.loadDevices();
      }
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

  Future<void> _checkRootAndRetry() async {
    final hybrid = widget.service as HybridBacklightService;
    final rootAvailable = await hybrid.isRootAvailable();
    if (!mounted) return;

    setState(() {
      _rootChecked = true;
      _rootAvailable = rootAvailable;
    });

    if (rootAvailable) {
      setState(() => _rootMode = true);
      await _loadDevices();
    }
  }

  Future<void> _enableRootMode() async {
    final hybrid = widget.service as HybridBacklightService;
    final rootAvailable = await hybrid.isRootAvailable();
    if (!mounted) return;

    setState(() {
      _rootChecked = true;
      _rootAvailable = rootAvailable;
      if (rootAvailable) {
        _rootMode = true;
      }
    });
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
      return _ErrorPanel(
        error: _loadError!,
        rootChecked: _rootChecked,
        rootAvailable: _rootAvailable,
        rootMode: _rootMode,
        onRetry: _loadDevices,
        onCheckRoot: _checkRootAndRetry,
      );
    }

    if (_devices.isEmpty) {
      return _NoDevicesPanel(
        rootChecked: _rootChecked,
        rootAvailable: _rootAvailable,
        rootMode: _rootMode,
        onRetry: _loadDevices,
        onCheckRoot: _checkRootAndRetry,
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
                            ? _pathLabel
                            : '${device.type} • $_pathLabel',
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

  String get _pathLabel {
    if (device.usesRoot) {
      return 'root • ${device.path}';
    }
    return device.path;
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

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.error,
    required this.rootChecked,
    required this.rootAvailable,
    required this.rootMode,
    required this.onRetry,
    required this.onCheckRoot,
  });

  final Object error;
  final bool rootChecked;
  final bool rootAvailable;
  final bool rootMode;
  final VoidCallback onRetry;
  final VoidCallback onCheckRoot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorMsg = error.toString();

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
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Backlight scan failed', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                errorMsg,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _RootStatusBadge(
                rootChecked: rootChecked,
                rootAvailable: rootAvailable,
                rootMode: rootMode,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCheckRoot,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: Text(rootChecked ? 'Retry root' : 'Check root'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: rootAvailable && !rootMode ? onCheckRoot : null,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Use root access'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoDevicesPanel extends StatelessWidget {
  const _NoDevicesPanel({
    required this.rootChecked,
    required this.rootAvailable,
    required this.rootMode,
    required this.onRetry,
    required this.onCheckRoot,
  });

  final bool rootChecked;
  final bool rootAvailable;
  final bool rootMode;
  final VoidCallback onRetry;
  final VoidCallback onCheckRoot;

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
              Icon(Icons.light_mode_outlined, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('No backlights found', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'No devices were found under /sys/class/backlight.\n'
                'This may happen on Android devices without root.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _RootStatusBadge(
                rootChecked: rootChecked,
                rootAvailable: rootAvailable,
                rootMode: rootMode,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCheckRoot,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: Text(rootChecked ? 'Retry root' : 'Check root'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: rootAvailable && !rootMode ? onCheckRoot : null,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Use root access'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RootStatusBadge extends StatelessWidget {
  const _RootStatusBadge({
    required this.rootChecked,
    required this.rootAvailable,
    required this.rootMode,
  });

  final bool rootChecked;
  final bool rootAvailable;
  final bool rootMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!rootChecked) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.help_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'Root status unknown',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    if (!rootAvailable) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.close, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Text(
            'Root not available',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          rootMode ? Icons.lock_open : Icons.lock_outline,
          size: 16,
          color: rootMode ? Colors.green : theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          rootMode ? 'Root mode active' : 'Root available',
          style: theme.textTheme.bodySmall?.copyWith(
            color: rootMode ? Colors.green : theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
