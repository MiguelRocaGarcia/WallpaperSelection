# Wallpapers

An iPhone app that finds wallpaper-worthy photos in your library: portrait, high-res, no prominent people, no pets, food, documents or screenshots. It shows them full-screen with the same crop iOS uses for wallpapers. Swipe right to add one to a **Wallpapers** album, left to skip.

All analysis runs on the iPhone with Apple's Vision framework.

## One-time setup

1. Install **Xcode** from the Mac App Store and open it once to finish installing components.
2. Xcode ▸ Settings ▸ Accounts ▸ **+** ▸ sign in with your Apple ID. A free account is enough.
3. Install XcodeGen and generate the project:
   ```sh
   brew install xcodegen
   xcodegen generate
   open WallpaperSelection.xcodeproj
   ```
4. In Xcode select the **WallpaperSelection** target ▸ *Signing & Capabilities* ▸ Team: *(your name) (Personal Team)*.
   If the bundle ID is taken, change `com.miguelroca.wallpaperselection` to something unique.

## Run on your iPhone

1. Connect the iPhone by USB and unlock it. Tap **Trust** if asked.
2. On the iPhone: Settings ▸ Privacy & Security ▸ **Developer Mode** ▸ On. The iPhone restarts.
3. In Xcode pick your iPhone as the run destination and press **Run** (⌘R).
4. The first time, the iPhone will refuse to open the app. Go to Settings ▸ General ▸ VPN & Device Management ▸ your Apple ID ▸ **Trust**, then run again.
5. Allow **Full Access** to Photos when asked.

With a free Apple ID the app stops launching after **7 days**. Connect the phone and press Run again to refresh it. Your swipes are kept.

## Use it as your wallpaper

Lock Screen ▸ touch and hold ▸ **+** ▸ **Photo Shuffle** ▸ choose the **Wallpapers** album ▸ pick how often it changes.

## How filtering works

1. **Metadata** (instant): portrait only, not a screenshot, shorter side ≥ 1080 px (configurable), not already in the album or skipped.
2. **Vision** on a 512 px thumbnail:
   - Person and face boxes: a photo is skipped if any box covers more than 2% of the image or is taller than 20% of it. Both are adjustable in Settings. Small, distant people are allowed.
   - Animal detection plus image classification for pets, food, documents and receipts.
   - Text coverage for signs, menus and screens.
3. Results are cached (`Application Support/decisions.json`), so each photo is analyzed only once. Changing thresholds re-applies them without re-analyzing.

## Tests

```sh
xcodegen generate
UDID=$(xcrun simctl create "WP iPhone 16" com.apple.CoreSimulator.SimDeviceType.iPhone-16)
scripts/seed-simulator.sh $UDID      # erases the simulator and loads the test photos
xcodebuild test -scheme WallpaperSelection -destination "id=$UDID"
```

- **FilterTests**: threshold and metadata rules.
- **VisionFilterTests**: runs the real Vision checks on the photos in `WallpaperSelectionTests/Fixtures/`. They're sorted into folders by expected outcome: `keep`, `person`, `animal`, `food`, `text` and `metadata`.
- **SwipeFlowUITests**: drives the app end to end. It swipes through the whole seeded library, then checks undo, the album grid, removing a photo from the album, Settings, and that decisions persist after a relaunch.

The test photos come from Wikimedia Commons under open licences. Credits are in [`WallpaperSelectionTests/Fixtures/ATTRIBUTION.md`](WallpaperSelectionTests/Fixtures/ATTRIBUTION.md).

Simulator limitation: image classification, which catches food and documents, can't run in the simulator. There, those checks are skipped and such photos still appear. On a real iPhone they're filtered.
