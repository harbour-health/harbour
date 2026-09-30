# App lock

## What it is

An optional local app lock with Face ID (Touch ID on supported devices) or a four-digit app PIN. It gates Harbour's interface on launch and after the app enters the background.

## How it works

Settings → App lock offers Off, Face ID, and PIN. Enabling biometrics requires enrolled biometrics and a successful iOS authentication challenge. Subsequent challenges use `deviceOwnerAuthentication`, which supports the phone's passcode as an OS-managed fallback. Harbour never reads biometric data or the device passcode. See [Apple's authentication policy](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication) and [Face ID integration guidance](https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id).

PIN entry uses four masked slots and a large number pad, with delete and automatic submission after the fourth digit. Setup asks for a new PIN, then a second entry to confirm it; mismatch returns to the first step. There are no visible or hidden text fields. Slots announce only the number of digits entered to accessibility. The layout becomes more compact on short screens.

A random 32-byte salt and PBKDF2-HMAC-SHA256 verifier (200,000 rounds, 32 bytes) are saved in Keychain; the PIN itself is not saved. Derivation runs off the main actor. Comparison accumulates byte differences rather than returning on the first mismatch. The fifth failed attempt starts a 30-second delay; further failures double the delay up to one hour. Failure count and retry deadline persist with the verifier, including across process restarts. This is an application retry limit, not a hardware-backed attempt counter.

New credentials include `pinLength: 4`. An older six-digit prototype credential without that field remains verifiable using six slots, so updating the app cannot silently disable its lock or strand its archive. Changing that legacy PIN through Settings creates a new four-digit credential. New setup always uses four digits.

The Keychain item uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Apple's [accessibility documentation](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly) defines device-unlocked availability and prevents migration to another device. There is no synchronizable attribute. Existing items are updated without deleting them first. Keychain or decoding errors keep the interface locked rather than reverting to Off.

Changing or disabling an existing lock first verifies its current credential. Successful verification grants a three-minute, in-memory configuration authorization; backgrounding revokes it. This gives time to enter and confirm a new PIN without removing the current lock first. Each authentication attempt also carries a generation ID, so cancelled or late callbacks cannot unlock a later session. Locking invalidates `LAContext`, replaces the navigation tree, dismisses record editors, clears share presentation, and cancels chat inference and voice through view teardown.

An opaque, separate non-key window covers the scene while inactive or backgrounded, including presented sheets. It displays only Harbour's mark. An active iOS authentication challenge is exempt while inactive so the system dialog remains usable; entering the background still revokes the challenge. The accessibility tree is hidden while inactive.

This is a UI access gate. The archive continues to use its existing iOS complete file protection; the app PIN is not an archive encryption key. Copies exported to other apps are outside this gate. A forgotten app PIN has no in-app reset bypass. Do not assume deleting and reinstalling the app removes a Keychain item. A recovery product flow would need a deliberate data-loss/credential policy before adding it.

## How to change it

`Harbour/AppLock.swift` owns authentication, Keychain storage, retry state, and the lock/settings views. `LockShell` in `HarbourApp.swift` owns lifecycle gating and the privacy curtain. Add configuration transitions through the authenticated manager methods; never mutate the selected mode directly from a view. Preserve the generation checks on every awaited authentication or derivation.

`HarbourLockTests` exercises actual Keychain-backed PIN setup, mismatch rejection, masked four-slot entry without text fields, delete, automatic incorrect/correct unlock, backgrounding with an open editor, persisted throttling, and verification before disabling. It leaves the fictional test installation with the lock Off. `HarbourFreshScreensTests` verifies that unavailable Face ID leaves the mode Off and displays the OS error. Simulator results do not verify Face ID matching, device passcode fallback, or physical-device app-switcher snapshots.

## Configuration

Keychain service: `com.matteopolak.harbour.app-lock`; account: `configuration`. `Info.plist` supplies `NSFaceIDUsageDescription`. Salt size, PBKDF2 rounds, PIN length, authorization lifetime, and backoff constants are in `AppLock.swift`. No server, environment variable, developer unlock flag, or plaintext PIN preference is involved.

```sh
xcodebuild -project Harbour.xcodeproj -scheme Harbour \
  -destination 'platform=iOS Simulator,name=Harbour QA' \
  -only-testing:HarbourUITests/HarbourLockTests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

## Dependencies

LocalAuthentication, Security/Keychain, CommonCrypto, SwiftUI, UIKit scene windows, and the shared appearance/Harbour mark. Physical Face ID and device passcode acceptance still require a signed device run.
