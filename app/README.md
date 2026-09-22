# Remote for Mac

A small macOS 27 menu bar app that uses a USB-C Siri Remote (3rd generation, A2854) to control presentations and common Mac actions.

Open `RemoteForMac.xcodeproj`, select the `RemoteForMac` scheme, and run it. The app requests Accessibility and Input Monitoring access on first launch. For the first connection, put the remote in pairing mode by holding **Back + Volume Up** for five seconds, then pair `siriremote` in **System Settings → Bluetooth**. macOS exposes its controls to the app after the system pairing completes.

Keep the selected development team and the `com.local.RemoteForMac` bundle identifier unchanged. macOS associates Device Control and Data Access grants with that signed identity, so subsequent launches and rebuilds do not ask again.

The app deliberately uses the private `MultitouchSupport` framework for clickpad gestures, so it is intended for direct distribution rather than the Mac App Store.

## Release

Install a Developer ID Application certificate for the selected Xcode team and save notarization credentials once:

```bash
xcrun notarytool store-credentials "RemoteForMac" --apple-id "YOUR_APPLE_ID" --team-id "9GALM9GLFA"
```

Enter an app-specific password when prompted. This is a one-time setup and is separate from the signing certificate.

The Sparkle update signing key is stored in the login Keychain under the account `RemoteForMac`. If it ever needs to be created on a new release machine, resolve the project packages in Xcode and run:

```bash
~/Library/Caches/RemoteForMac/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account RemoteForMac
```

Then create the signed and notarized disk image:

```bash
./release.sh
```

The script uses manual distribution signing and asks Keychain to select the team's installed Developer ID Application certificate. It archives a Release build with Hardened Runtime, creates and notarizes the disk image, staples the notarization ticket, verifies the result, and signs the update with Sparkle. It atomically replaces `web/public/Remote.for.Mac.dmg` and regenerates `web/public/appcast.xml` with the website download URL. Commit both generated files and deploy the web project; the fixed filename always serves the latest version.

Set `NOTARY_PROFILE`, `TEAM_ID`, `SIGNING_IDENTITY`, `SPARKLE_ACCOUNT`, or `SPM_CACHE_DIR` in the environment when using different release credentials or cache locations.
