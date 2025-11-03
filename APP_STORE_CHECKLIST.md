# WRKT App - App Store Submission Checklist

**Last Updated:** October 27, 2025  
**Status:** NOT READY FOR SUBMISSION

---

## PHASE 1: CRITICAL FIXES (Must do - 2-3 weeks)

### App Configuration
- [ ] Verify Info.plist configuration (auto-generated or explicit)
- [ ] Add NSHealthUpdateUsageDescription to privacy keys
- [ ] Add NSLocationWhenInUseUsageDescription (if needed)
- [ ] Update bundle identifier from `dlo.WRKT` to proper identifier
- [ ] Create complete app icon set (all required sizes)
- [ ] Design and implement launch screen
- [ ] Verify all entitlements are correct

### Code Quality - Critical Crashes
- [ ] Replace `fatalError()` in WRKTApp.swift line 59 with graceful error handling
- [ ] Fix WorkoutStorage.swift force unwraps (lines 103+) - test on all iOS versions
- [ ] Fix CalendarMonthView.swift force unwrap of `days.last!`
- [ ] Fix SetRowViews.swift force unwrap of `all.first!`
- [ ] Fix WinScreenCoordinator.swift array access safety
- [ ] Test all crash scenarios on physical device

### Debug Code Removal
- [ ] Remove all 340+ print() statements from production code
  - [ ] AppShellView.swift (20+)
  - [ ] ExerciseSessionViewModel.swift (10+)
  - [ ] HealthKitManager.swift (15+)
  - [ ] ExerciseRepository.swift (bootstrap logs)
  - [ ] All other files with print()
- [ ] Option: Replace critical prints with os_log for debugging only
- [ ] Test app performance after removing logs

### Data Security
- [ ] Implement NSFileProtectionComplete for user data
- [ ] Verify SwiftData encryption status
- [ ] Remove debug `wipeAllDevOnly()` or rename appropriately
- [ ] Test data persistence and security

---

## PHASE 2: COMPLIANCE & DOCUMENTATION (1-2 weeks)

### Privacy & Permissions
- [ ] Write Privacy Policy document
- [ ] Document all data collected from HealthKit
- [ ] Clarify data retention period
- [ ] Test privacy permission prompts on device
- [ ] Implement proper "Delete Account/Data" feature
- [ ] Test data deletion functionality
- [ ] Document GDPR/CCPA compliance measures

### Error Handling & User Communication
- [ ] Add user-friendly error messages (not console prints)
- [ ] Handle HealthKit permission denied gracefully
- [ ] Show sync error states in UI
- [ ] Implement retry logic for failed operations
- [ ] Test error scenarios

### Incomplete Features
- [ ] Remove PlannerDebugView.swift completely
- [ ] Remove any debug UI components
- [ ] Implement Step 6 (Review) in PlannerSetupCarouselView
- [ ] Verify SearchView is fully functional
- [ ] Test YouTube player error handling
- [ ] Add fallback for YouTube load failures

---

## PHASE 3: QUALITY ASSURANCE (1-2 weeks)

### Testing
- [ ] Increase unit test coverage to 50%+ for critical paths
- [ ] Write tests for HealthKitManager
- [ ] Write tests for data persistence
- [ ] Write tests for error scenarios
- [ ] Add UI tests for key user flows
- [ ] Test on device with various network conditions

### Performance
- [ ] Profile app startup time
- [ ] Measure memory usage with exercise database
- [ ] Test on older devices (iPhone SE, iPhone 11)
- [ ] Profile HealthKit sync operations
- [ ] Test with large datasets (100+ workouts)

### Device & OS Testing
- [ ] Test on physical iPhone (minimum target iOS version)
- [ ] Test on iPhone 14 Pro Max (largest)
- [ ] Test on iPhone SE (smallest)
- [ ] Test on iPad (if supporting)
- [ ] Test on iOS minimum version + current version
- [ ] Test Dark Mode
- [ ] Test Dynamic Type (accessibility)

### Integration Testing
- [ ] Test HealthKit authorization flow
- [ ] Test workout logging flow
- [ ] Test route mapping with HealthKit data
- [ ] Test onboarding flow end-to-end
- [ ] Test goal setup and weekly tracking
- [ ] Test data persistence across app restarts

---

## PHASE 4: APP STORE PREPARATION (1 week)

### Metadata & Screenshots
- [ ] Write compelling app description
- [ ] Create App Store screenshots (5+)
- [ ] Create app preview video (optional but recommended)
- [ ] Write promotional text
- [ ] Choose primary and secondary categories
- [ ] Select appropriate ratings

### Build & Testing
- [ ] Create Release build
- [ ] Run through Xcode validation
- [ ] Upload to TestFlight for beta testing
- [ ] Beta test with 10-20 real users
- [ ] Collect feedback and fix critical issues
- [ ] Test in-app purchases (if applicable)

### App Store Compliance
- [ ] Review App Store Review Guidelines
- [ ] Ensure HealthKit compliance
- [ ] Document all permissions and usage
- [ ] Prepare responses to potential review questions
- [ ] Set up app support website/email
- [ ] Create terms of service (if needed)
- [ ] Document privacy policy URL

### Final QA
- [ ] Full end-to-end user flow test
- [ ] Test all permission prompts
- [ ] Verify crash reporting is disabled in production
- [ ] Check for any hardcoded test data
- [ ] Verify analytics tracking is appropriate
- [ ] Test on various network conditions
- [ ] Test with screen recording disabled

---

## PHASE 5: SUBMISSION

- [ ] Final review of all changes
- [ ] Increment version/build number
- [ ] Create release notes
- [ ] Submit to App Store
- [ ] Monitor for approval (48-72 hours)
- [ ] Prepare for App Store submission responses
- [ ] Set up app monitoring post-launch

---

## CRITICAL ISSUE TRACKING

### BLOCKER Issues (Must fix for submission)

| Issue | File | Priority | Status |
|-------|------|----------|--------|
| fatalError on startup | App/WRKTApp.swift | 🔴 CRITICAL | ❌ TODO |
| 340+ print statements | Multiple | 🔴 CRITICAL | ❌ TODO |
| 56 force unwraps | Multiple | 🔴 CRITICAL | ❌ TODO |
| Missing privacy descriptions | xcodeproj | 🔴 CRITICAL | ❌ TODO |
| Missing app icons | Resources/Assets | 🔴 CRITICAL | ❌ TODO |
| Bundle identifier | xcodeproj | 🟠 HIGH | ❌ TODO |
| Data security (file protection) | Persistence | 🔴 CRITICAL | ❌ TODO |

### HIGH Priority Issues

| Issue | File | Status |
|-------|------|--------|
| Debug UI components | PlannerDebugView | ❌ TODO |
| HealthKit error handling | HealthKitManager | ❌ TODO |
| YouTube player fallback | YouTubeInlinePlayer | ❌ TODO |
| Memory leak audit | Various | ❌ TODO |
| Missing launch screen | App | ❌ TODO |

---

## VERIFICATION CHECKLIST

Before submitting to App Store, verify:

### Build Configuration
- [ ] Release build configured
- [ ] Debug symbols stripped
- [ ] Optimization level set to `-Os`
- [ ] No debug code in release build
- [ ] Code signing configured correctly

### Deployment Target
- [ ] Minimum iOS version documented
- [ ] Tested on minimum version
- [ ] All APIs used are available on min version

### Privacy & Security
- [ ] All privacy descriptions present
- [ ] No hardcoded API keys or secrets
- [ ] No test accounts in production code
- [ ] Data encryption implemented
- [ ] No unnecessary device data collection

### Performance
- [ ] App launches in <5 seconds
- [ ] Memory usage <100MB average
- [ ] No significant CPU/battery drain
- [ ] Network requests have timeouts

### User Experience
- [ ] App name is clear and descriptive
- [ ] Icon is professional and recognizable
- [ ] Onboarding is clear (tested with new user)
- [ ] All interactive elements respond quickly
- [ ] Error messages are user-friendly

---

## SIGN-OFF

- **Code Review:** ❌ TODO
- **QA Testing:** ❌ TODO
- **Privacy Review:** ❌ TODO
- **Security Review:** ❌ TODO
- **Performance Review:** ❌ TODO
- **Final Approval:** ❌ TODO

**Ready for App Store?** ❌ NO (As of October 27, 2025)

---

## NOTES

- Estimated timeline to ready: 5-8 weeks
- All critical issues must be fixed before TestFlight
- Plan for App Store rejection scenarios
- Keep communication channel with App Review ready
- Document all changes in release notes

For detailed analysis, see: `APP_STORE_DEPLOYMENT_READINESS.md`
