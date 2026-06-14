# Development scripts

The scripts in `scripts/windows`, `scripts/linux`, and `scripts/macos` are intentionally synchronized by name and behavior.

## setup-devenv

Installs or verifies the tools needed to develop `platform_serial`:

- Git
- Flutter SDK and Dart SDK
- Android Studio and Android SDK tooling
- Oh My Posh with the `M365Princess` theme
- Shell startup integration for Oh My Posh

| Platform | Command |
| --- | --- |
| Windows | `scripts/windows/setup-devenv.ps1 -Yes` |
| Linux | `scripts/linux/setup-devenv --yes` |
| macOS | `scripts/macos/setup-devenv --yes` |

Common behavior:

- idempotent: already-installed tools are skipped;
- colorful output and emoji status markers;
- `--help` / `-h` prints usage;
- `--dry-run` shows actions without changing the system;
- `--skip-android-studio` and `--skip-oh-my-posh` opt out of optional installs.
