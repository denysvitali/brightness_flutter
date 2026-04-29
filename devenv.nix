{ pkgs, lib, ... }:

{
  packages = [
    pkgs.git
    pkgs.flutter
    pkgs.jdk21
  ];

  android = {
    enable = true;
    buildTools.version = [ "35.0.0" ];
    emulator.enable = false;
    ndk = {
      enable = true;
      version = [ "28.2.13676358" ];
    };
    systemImages.enable = false;
  };

  env = {
    DART_SDK = "${pkgs.flutter.out}/bin/cache/dart-sdk";
    FLUTTER_ROOT = lib.mkForce "${pkgs.flutter.out}";
  };
}
