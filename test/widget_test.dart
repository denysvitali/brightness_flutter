import 'package:brightness_flutter/backlight_service.dart';
import 'package:brightness_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBacklightService implements BacklightService {
  FakeBacklightService(this.devices);

  final List<BacklightDevice> devices;
  final writes = <String, int>{};

  @override
  Future<List<BacklightDevice>> loadDevices() async => devices;

  @override
  Future<BacklightDevice> setBrightness(
    BacklightDevice device,
    int brightness,
  ) async {
    writes[device.path] = brightness;
    return device.copyWith(
      brightness: brightness,
      actualBrightness: brightness,
    );
  }
}

void main() {
  testWidgets('shows one slider per backlight device', (tester) async {
    final service = FakeBacklightService([
      const BacklightDevice(
        name: 'intel_backlight',
        path: '/sys/class/backlight/intel_backlight',
        brightness: 40,
        maxBrightness: 100,
        actualBrightness: 38,
        type: 'raw',
      ),
      const BacklightDevice(
        name: 'acpi_video0',
        path: '/sys/class/backlight/acpi_video0',
        brightness: 5,
        maxBrightness: 10,
      ),
    ]);

    await tester.pumpWidget(BrightnessApp(service: service));
    await tester.pump();

    expect(find.text('intel_backlight'), findsOneWidget);
    expect(find.text('acpi_video0'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });
}
