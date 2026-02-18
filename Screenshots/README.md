# Screenshot Mock Views

**TEMPORARY FILES FOR APP STORE SCREENSHOTS**

These files create mock versions of the social features for taking clean screenshots without real user data.

## How to Use

### 1. Enable Screenshot Mode

Open `Features/Social/Views/SocialView.swift` and change line 12:

```swift
private let USE_MOCK_VIEWS_FOR_SCREENSHOTS = true  // Change from false to true
```

### 2. Build and Run

Build the app and navigate to the Social tab. You'll now see:
- **Feed tab**: Mock workout posts from fictional users
- **Compete tab**: Mock battles with sample data
- **Friends tab**: Mock friends list with activity indicators

### 3. Take Screenshots

Use iPhone simulator or device to capture screenshots showing:
- Social feed with posts
- Active battles
- Friends list
- Battle detail views (if needed)

**Recommended devices for screenshots:**
- iPhone 15 Pro Max (6.7")
- iPhone 15 Pro (6.1")
- iPhone SE (5.5")

### 4. Disable Screenshot Mode

After taking screenshots, **IMMEDIATELY** change back:

```swift
private let USE_MOCK_VIEWS_FOR_SCREENSHOTS = false  // Change back to false
```

### 5. Delete These Files

Once screenshots are done and uploaded to App Store Connect, delete this entire folder:

```bash
rm -rf Screenshots/
```

And remove the screenshot flag from `SocialView.swift`:
- Delete lines 10-13 (the flag and comments)
- Remove the `if USE_MOCK_VIEWS_FOR_SCREENSHOTS` conditional, keeping only the `else` branch

## Files in This Folder

- `MockFeedView.swift` - Mock social feed with 5 sample posts (matches real FeedView)
- `MockCompeteView.swift` - Mock compete hub with battles and challenges (matches real UnifiedCompeteView)
- `MockFriendsHubView.swift` - Mock friends hub with activity feed (matches real FriendsHubView)
- `README.md` - This file (delete after use)

## ⚠️ Important

**DO NOT SUBMIT TO APP STORE WITH SCREENSHOT MODE ENABLED**

Always verify `USE_MOCK_VIEWS_FOR_SCREENSHOTS = false` before archiving for submission.

## Sample Data

The mock views include:
- **Feed**: 5 diverse workout posts with different exercises and engagement
- **Compete**: 3 active battles, 2 pending invites, 2 recommended challenges, plus stats grid
- **Friends**: Friend requests, friends list link, and 5 recent friend activities

All names, usernames, and data are completely fictional and do not represent real users.

## Visual Accuracy

These mock views are styled to match the actual app views exactly:
- **Feed**: Uses real PostCard styling with DS.Semantic colors, FAB, profile button with notification badge
- **Compete**: Matches UnifiedCompeteView with stat tiles, creation grid, carousels
- **Friends**: Matches FriendsHubView List-based layout with sections and badges
