# Get the app building in Xcode after switching to Firebase

Use this checklist after moving from Supabase to Firebase so the iOS build works again.

---

## 1. Confirm Firebase config files

- **`ios/Runner/GoogleService-Info.plist`**  
  Must exist and match your Firebase iOS app. Your project already has it with:
  - `BUNDLE_ID`: `com.example.myFirstApp`
  - `PROJECT_ID`: `potluck-app-1a9f1`

- In **Xcode**: Runner target → **Build Phases** → **Copy Bundle Resources** should include `GoogleService-Info.plist`. (It’s already in your `project.pbxproj`.)

---

## 2. Clean and reinstall dependencies

From the **project root** (e.g. `my_first_app/`):

```bash
# Clean Flutter build and get packages
flutter clean
flutter pub get

# Reinstall iOS CocoaPods (required after dependency changes)
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
```

If `pod install` fails with **Unicode/Encoding errors**, set UTF-8 and retry:

```bash
cd ios
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
pod install
cd ..
```

(You can add `export LANG=en_US.UTF-8` to `~/.zshrc` to avoid this in future.)

If you use a Mac with Apple Silicon and see other pod issues, try:

```bash
cd ios
arch -x86_64 pod install
cd ..
```

---

## 3. Open the workspace (not the project)

- Always open **`ios/Runner.xcworkspace`** in Xcode, not `Runner.xcodeproj`.
- Opening the workspace ensures CocoaPods (Firebase, etc.) are part of the build.

---

## 4. Build from Xcode or Flutter

**Option A – Flutter (no code signing):**

```bash
flutter build ios --no-codesign
```

**Option B – Run on simulator:**

```bash
flutter run
```

**Option C – Xcode:**

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select a simulator or a connected device.
3. Pick the **Runner** scheme.
4. Product → Build (⌘B), or Run (⌘R).

---

## 5. Code signing (for a real device)

- In Xcode: select **Runner** → **Signing & Capabilities**.
- Set your **Team** and ensure **Automatically manage signing** is on (or configure a provisioning profile).
- Bundle ID must stay **`com.example.myFirstApp`** to match `GoogleService-Info.plist`.

---

## 6. App startup (Firebase is already wired)

In your app:

- `main()` calls `await Firebase.initializeApp();` (no options needed; iOS uses `GoogleService-Info.plist`).
- You use `FirebaseService` for auth and Firestore; Supabase is no longer in `pubspec.yaml`.

So after a successful build, the app should start and use Firebase. No extra “get app started” steps are required beyond fixing the build.

---

## If Xcode still fails

1. **Note the exact error**  
   Build log (Report navigator or `flutter build ios` in Terminal) – e.g. “No such module”, signing error, missing plist.

2. **Common fixes:**
   - **“No such module ‘Firebase…’”** → Run `pod install` in `ios/` again; open `Runner.xcworkspace` and build.
   - **“GoogleService-Info.plist not found”** → Ensure the file is under `ios/Runner/` and listed in **Copy Bundle Resources**.
   - **Signing errors** → Set Team and bundle ID in Signing & Capabilities.
   - **Swift/version errors** → Xcode and `ios/Podfile` both use iOS 13.0; update Xcode if it’s very old.

3. **Nuclear option:**  
   Delete `ios/Pods`, `ios/Podfile.lock`, and `ios/.symlinks`, then run `flutter pub get`, `cd ios && pod install`, and build again from `Runner.xcworkspace`.

---

## Summary checklist

- [ ] `ios/Runner/GoogleService-Info.plist` present and bundle ID = `com.example.myFirstApp`
- [ ] `flutter clean && flutter pub get`
- [ ] `cd ios && rm -rf Pods Podfile.lock && pod install && cd ..`
- [ ] Open **`ios/Runner.xcworkspace`** in Xcode (not the `.xcodeproj`)
- [ ] Build Runner scheme; fix signing if building for a device

After that, the app should build and start using Firebase.
