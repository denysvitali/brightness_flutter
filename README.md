# Brightness Flutter

A small Flutter app that controls Linux backlight devices exposed under
`/sys/class/backlight`.

## Development

```sh
devenv shell -- flutter pub get
devenv shell -- flutter test
devenv shell -- flutter build apk --release --no-pub --target-platform android-arm64
devenv shell -- flutter build linux --debug --no-pub
```

## Android release signing

Generate a release keystore and GitHub secret values:

```sh
./tool/generate_android_keystore.sh
```

Save the four values from `.android/release-keystore-secrets.txt` as GitHub
Actions secrets: `KEYSTORE_BASE64`, `KEYSTORE_STORE_PASSWORD`,
`KEYSTORE_KEY_PASSWORD`, and `KEYSTORE_KEY_ALIAS`.

Writing brightness usually requires root permissions or a udev/logind rule that
allows the user to write each device's `brightness` file.
