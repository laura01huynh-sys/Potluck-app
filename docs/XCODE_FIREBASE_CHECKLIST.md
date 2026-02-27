# Xcode + Firebase build checklist

Checked against your project. Fix any items that don’t match.

---

## 1. GoogleService-Info.plist

- **Location:** `ios/Runner/GoogleService-Info.plist` — present.
- **Xcode:** File is in the Runner target and in **Copy Bundle Resources** (project.pbxproj has `GoogleService-Info.plist in Resources`).
- **Bundle ID:** Plist has `com.example.myFirstApp`; ensure the Runner target’s bundle ID in Xcode is the same.

**Action:** In Xcode, select the Runner target → General → confirm **Bundle Identifier** is `com.example.myFirstApp`. No change needed if it already matches.

---

## 2. Firebase SDK (CocoaPods)

- **Podfile:** Uses `flutter_install_all_ios_pods` — Firebase pods come from Flutter plugins. Correct.
- **Pods:** `Podfile.lock` shows Firebase (FirebaseCore, FirebaseAuth, FirebaseFirestore, etc.) and Flutter pods.

**Action:** Always open **`ios/Runner.xcworkspace`** (not `Runner.xcodeproj`) when building in Xcode. Run from project root:
```bash
cd ios
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
pod install
cd ..
```

---

## 3. Firebase initialization

- **Dart:** `main()` calls `await Firebase.initializeApp();` — correct.
- **iOS (optional but recommended):** `AppDelegate.swift` was updated to call `FirebaseApp.configure()` so native Firebase is configured before plugins. This can resolve “no default app” or linker/load issues.

---

## 4. Clean build and Derived Data

Do this when the build is stuck or fails with odd errors:

1. In **Xcode:** Product → **Clean Build Folder** (Shift+Cmd+K).
2. **Quit Xcode** (Cmd+Q).
3. In **Finder**, go to `~/Library/Developer/Xcode/DerivedData/`.
4. Delete the folder whose name starts with your project (e.g. contains `Runner-` or your app name). Or delete the whole `DerivedData` folder to clear everything.
5. Reopen **`ios/Runner.xcworkspace`** and build again (Cmd+B).

---

## 5. Build settings (linker / search paths)

- **Other Linker Flags:** Runner target gets flags from CocoaPods via the Pods xcconfig files. The project uses `$(inherited)` so Pods flags are applied. No manual change needed unless you see linker errors.
- **Framework / Library Search Paths:** Handled by CocoaPods when you open the `.xcworkspace`.

If you see “undefined symbol” or “framework not found” errors, in Xcode: Runner target → Build Settings → search “Other Linker Flags” and ensure **$(inherited)** is there.

---

## 6. Dependencies

- **Pods:** After changing `pubspec.yaml` or the Podfile, run:
  ```bash
  flutter pub get
  cd ios && pod install && cd ..
  ```
- **Xcode:** Keep Xcode up to date (e.g. latest stable from the Mac App Store).

---

## 7. Compiler / linker errors

- In Xcode, open the **Issue Navigator** (speech bubble icon) or the **Report navigator** (last tab) and read the **exact** error (e.g. missing symbol, duplicate symbol, “framework not found”, “no such module”).
- Search that exact message online; it usually points to a specific fix (e.g. missing `FirebaseApp.configure()`, wrong scheme, or opening `.xcodeproj` instead of `.xcworkspace`).

---

## 8. Concurrent builds

- Don’t run the app from **both** Cursor (Run/Debug) and Xcode (or two `flutter run` processes) at the same time.
- If you see “Xcode build failed due to concurrent builds”: stop the other run, quit Xcode if you’re using `flutter run`, then run again from a single place.

---

## Summary

| Item                         | Status in your project |
|-----------------------------|-------------------------|
| GoogleService-Info.plist    | Present and in target   |
| Open .xcworkspace           | Use Runner.xcworkspace  |
| CocoaPods (pod install)     | Configured via Flutter |
| Dart Firebase init          | Yes in main()           |
| AppDelegate Firebase init  | Added (recommended)      |
| Clean / DerivedData         | Do when build is stuck  |
| Single build (no concurrent)| Avoid two launchers     |

If it still fails, the **exact** error text from Xcode’s Issue Navigator or from `flutter build ios` in the terminal is needed to narrow it down.
