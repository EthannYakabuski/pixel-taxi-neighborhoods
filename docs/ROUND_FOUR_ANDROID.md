# Round 4: Android App Bundle and native architectures

The default `Android` export now produces `.aab` with Gradle. Previously x86
32-bit was selected without its x86_64 counterpart. ARM64 alone does not provide
the missing x86 64-bit native code. x86_64 is now enabled alongside the existing
ARM64/x86 selection; other owner configuration is preserved.

```sh
python tools/verify_android_bundle.py --preset export_presets.cfg
godot --headless --path . --install-android-build-template --export-debug Android build/local-next-update/android/game-debug.aab
python tools/verify_android_bundle.py build/local-next-update/android/game-debug.aab
```

Create a new output directory before exporting. The validator checks actual
bundled ELF class/machine, Godot runtime presence and every 32-bit native library's
matching 64-bit counterpart. CI fails if preset or built native coverage regresses.
This is build validation, not an upload or a claim of Google Play acceptance.

The debug bundle above is test-signed. The owner must use their private release
keystore outside Git, choose an unused higher version code, configure production
services and verify all current Play requirements before uploading a release AAB.
No signing keys, credentials or private machine paths belong in the repository.
Existing version codes, service IDs and target SDK choices are preserved; the
build receipt records the target actually tested. Earlier APK/native QA remains
historical evidence and must not be attributed to a newly exported bundle.

For direct emulator installation only, Godot's export dialog may temporarily use
APK format and an `.apk` destination with the same paired ABIs; restore the AAB
default before committing. Do not upload an old APK/AAB that predates this fix.
Google Play can also flag another active old APK in the same release: inspect
the exact version reported by the console if it still reports a 32-bit artifact.

References: [Android 64-bit requirements](https://developer.android.com/google/play/requirements/64-bit),
[Godot Android export](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_android.html).
