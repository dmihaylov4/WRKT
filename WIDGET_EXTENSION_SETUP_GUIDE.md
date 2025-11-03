# Widget Extension Setup Guide

## Step 1: Create Widget Extension Target

**IMPORTANT: This must be done in Xcode - cannot be automated via CLI**

### Instructions:

1. **Open WRKT.xcodeproj in Xcode**

2. **Add Widget Extension Target**
   - File → New → Target
   - Select "Widget Extension"
   - Click "Next"

3. **Configure the Extension**
   - Product Name: `WRKTWidgets`
   - Team: (Your team)
   - Organization Identifier: `com.dmihaylov.trak`
   - Bundle Identifier: `com.dmihaylov.trak.WRKTWidgets`
   - ✅ **Include Live Activity**: YES (IMPORTANT!)
   - Language: Swift
   - Click "Finish"

4. **Activate Scheme**
   - When prompted "Activate 'WRKTWidgets' scheme?", click **"Activate"**

5. **Delete Default Files** (we'll replace them)
   - Delete `WRKTWidgets.swift` (the default generated file)
   - Delete `WRKTWidgetsBundle.swift` (if present)
   - Keep `Assets.xcassets` and `Info.plist`

---

## Step 2: Configure App Groups

**Both the main app AND the widget extension need to share data**

### For MAIN APP (WRKT):

1. Select **WRKT** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Click **+** to add a new group:
   - `group.com.dmihaylov.trak.shared`
6. ✅ Check the checkbox to enable it

### For WIDGET EXTENSION (WRKTWidgets):

1. Select **WRKTWidgets** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Click **+** to add a new group:
   - `group.com.dmihaylov.trak.shared` (SAME as main app)
6. ✅ Check the checkbox to enable it

---

## Step 3: Enable Live Activities in Main App

1. Select **WRKT** target
2. Open `Info.plist` (in the main app)
3. Add these two keys:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

**Or using Xcode GUI:**
- Right-click in Info.plist
- Add Row
- Key: "Supports Live Activities" → Value: YES
- Add Row
- Key: "Supports Live Activities Frequent Updates" → Value: YES

---

## Step 4: Add Files to Widget Target

After creating the Swift files, you need to add them to the correct targets:

### Files for WIDGET TARGET (WRKTWidgets):
- `RestTimerAttributes.swift` ✅ WRKTWidgets ✅ WRKT (both!)
- `RestTimerLiveActivity.swift` ✅ WRKTWidgets
- `RestTimerAppIntents.swift` ✅ WRKTWidgets ✅ WRKT (both!)
- `WRKTWidgetsBundle.swift` ✅ WRKTWidgets
- Any shared models/utilities ✅ Both targets

### Files for MAIN APP TARGET only (WRKT):
- `LiveActivityManager.swift` ✅ WRKT only
- Updated `RestTimerManager.swift` ✅ WRKT only

**How to add file to target:**
1. Select the file in Project Navigator
2. Open File Inspector (right panel)
3. Under "Target Membership", check the appropriate targets

---

## Step 5: Build Settings

### For WRKTWidgets target:

1. Select **WRKTWidgets** target
2. Go to **Build Settings**
3. Search for "Deployment Target"
4. Set **iOS Deployment Target**: `16.1` (minimum for Live Activities)

### For WRKT main app:

1. Keep existing deployment target (iOS 17.0 or whatever you have)
2. Live Activities will gracefully degrade on older iOS versions

---

## Step 6: Import ActivityKit

In files that use Live Activities, import:
```swift
import ActivityKit
import WidgetKit
import SwiftUI
```

---

## Verification Checklist

After setup, verify:

- [ ] WRKTWidgets target exists in project
- [ ] App Groups capability enabled on BOTH targets with SAME group ID
- [ ] Info.plist has Live Activities keys enabled
- [ ] iOS Deployment Target is 16.1+ for WRKTWidgets
- [ ] All files are added to correct targets
- [ ] Project builds without errors

---

## Common Issues

### "No such module 'ActivityKit'"
- Solution: Set iOS Deployment Target to 16.1+ for WRKTWidgets target

### "App group not found"
- Solution: Ensure EXACT same group ID on both targets: `group.com.dmihaylov.trak.shared`

### "File not found in widget"
- Solution: Check Target Membership in File Inspector, add to WRKTWidgets target

### Live Activity doesn't start
- Solution: Only works on PHYSICAL DEVICE, not simulator (except previews)

---

## Next Steps

After completing this setup:
1. Add the Swift files I'm creating
2. Build both targets
3. Run on physical device
4. Test rest timer Live Activity

---

**Status**: Manual setup required before proceeding with code files
**Estimated Time**: 10-15 minutes
