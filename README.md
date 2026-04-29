# Brightness Flutter

A small Flutter app that controls Linux backlight devices exposed under
`/sys/class/backlight`.

## Development

```sh
devenv shell -- flutter pub get
devenv shell -- flutter test
devenv shell -- flutter build apk --debug --no-pub
devenv shell -- flutter build linux --debug --no-pub
```

Writing brightness usually requires root permissions or a udev/logind rule that
allows the user to write each device's `brightness` file.
