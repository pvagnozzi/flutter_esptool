# Demo Application

The package includes a professional demonstration app:

- Path: `example/professional_esptool_demo`
- Theme modes: light and dark
- Splash screen: built-in startup gate
- Languages: `en`, `fr`, `es`, `pt`, `de`, `it`, `nl`, `ru`, `ar`, `he`, `zh`, `ja`, `ko`
- Features: connect, chip detect, MAC read, flash info, flash write, erase, MD5

Run:

```bash
cd example\professional_esptool_demo
flutter pub get
flutter run
```

The demo uses a scripted transport to simulate protocol responses and keep the app functional without hardware.
