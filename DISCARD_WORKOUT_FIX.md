# Discard Workout - Confirmation & Undo Fix ✅

## Problem
When users tapped "Discard Workout" button, the workout was immediately deleted without:
1. ❌ Confirmation dialog (accidental taps)
2. ❌ Undo option (no way to recover)

## Solution

### 1. Added Confirmation Dialogs
Both discard workout buttons now show a confirmation dialog:
- **Title**: "Discard Workout"
- **Message**: "Are you sure you want to discard this workout? You can undo this action."
- **Actions**:
  - "Discard Workout" (destructive/red)
  - "Cancel" (safe exit)

### 2. Added Undo Functionality
After confirming discard:
- **Toast appears** at bottom: "Workout discarded"
- **Undo button** available for 5 seconds
- Tapping "Undo" **restores the workout** exactly as it was
- **Haptic feedback** on successful undo

## Files Modified

### Core Logic
**`Features/WorkoutSession/Services/WorkoutStoreV2.swift`**
- Added `lastDiscardedWorkout` property to store workout before discarding
- Modified `discardCurrentWorkout()` to save workout and show undo toast
- Added `undoDiscardWorkout()` to restore discarded workout

### UI Components
**`Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutView.swift`**
- Added `showDiscardConfirmation` state
- Added confirmation dialog to discard button
- Now shows dialog before discarding

**`Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift`**
- Added `showDiscardConfirmation` state to main view
- Updated `OverlayBottomActions` to accept binding and show dialog
- Changed discard button to show confirmation instead of immediate discard
- Added confirmation dialog modifier

## User Flow

### Before Fix:
1. User taps "Discard Workout"
2. 💥 Workout instantly deleted (no confirmation)
3. 😢 No way to undo

### After Fix:
1. User taps "Discard Workout"
2. ⚠️ **Confirmation dialog appears**
3. User taps "Cancel" → Workout safe
4. OR user confirms → Workout discarded
5. 🎉 **Toast appears**: "Workout discarded" with Undo button
6. User has 5 seconds to tap "Undo"
7. Tapping Undo → Workout fully restored

## Where Discard Button Appears

1. **LiveWorkoutView** - Full-screen workout list view
   - Location: Bottom of screen, below "Slide to finish workout"

2. **LiveWorkoutOverlayCard** - Popup overlay card
   - Location: Bottom of card, below "Slide to finish workout"

Both locations now have identical confirmation + undo behavior!

## Testing

### Test Case 1: Confirmation Dialog
- [ ] Start a workout with exercises
- [ ] Tap "Discard Workout"
- [ ] Verify dialog appears with title and message
- [ ] Tap "Cancel" → workout still active
- [ ] Tap "Discard Workout" again → dialog appears
- [ ] Confirm discard → workout deleted

### Test Case 2: Undo Toast
- [ ] Start a workout
- [ ] Discard workout (confirm in dialog)
- [ ] Verify toast appears: "Workout discarded"
- [ ] Tap "Undo" within 5 seconds
- [ ] Verify workout is restored with all exercises intact
- [ ] Verify haptic feedback occurs

### Test Case 3: Auto-Dismiss
- [ ] Discard a workout
- [ ] Don't tap Undo
- [ ] Wait 5+ seconds
- [ ] Verify toast auto-dismisses
- [ ] Verify workout stays deleted

### Test Case 4: Both Locations
- [ ] Test discard from LiveWorkoutView (full screen)
- [ ] Test discard from LiveWorkoutOverlayCard (popup)
- [ ] Both should show same dialog and undo behavior

## Safety Improvements

✅ **Accidental taps prevented** - Must confirm in dialog
✅ **5-second undo window** - Recover from mistakes
✅ **Clear messaging** - Users know they can undo
✅ **Consistent UX** - Same behavior as workout deletion
✅ **Haptic feedback** - Tactile confirmation on undo

---

## Related Fixes
This fix completes the comprehensive deletion safety system:
1. ✅ Completed workout deletion (from detail view)
2. ✅ Active workout discard (this fix)
3. ✅ Set deletion with feedback (last set protection)
