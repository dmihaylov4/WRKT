# SourceKit False Positives in BarbellRealityView.swift

## What happening

SourceKit reports "Cannot find type X in scope" for types that exist and compile fine. Build succeeds. Only IDE squiggles are wrong.

## Affected lines (as of 2026-04-11)

| Line | Error | Actual type location |
|------|-------|---------------------|
| 18 | `EarnedPlateInfo` not found | `Features/Rewards/Models/BarbellModels.swift` |
| 20-23 | `EarnedPlate` not found | `Features/Rewards/Models/BarbellModels.swift` |
| 33 | `PlateRoleComponent` not found | `Features/Rewards/Views/BarbellEntityBuilder.swift` |
| 97 | `PlateTextures` not found | `Features/Rewards/Views/BarbellEntityBuilder.swift` |
| 111 | `DragPhase` / `.draggingPlate` not resolved | same file, defined elsewhere in module |
| 153 | `UIAccessibility` not found | UIKit — always available on iOS |

## Why

SourceKit parses files in isolation or with stale index. Cross-file types in same module fail resolution when:
- Index not rebuilt after adding/renaming file
- SourceKit daemon has stale cache
- File not yet part of resolved module graph in IDE session

SwiftData `@Model` types (`EarnedPlate`) and RealityKit `Component` types (`PlateRoleComponent`) trigger this more often — generated code from macros confuses indexer.

## Proof these are false positives

- `xcodebuild` succeeds with 0 errors
- App runs on device
- Errors disappear after full clean + reindex

## Fix (when IDE squiggles become unbearable)

1. Xcode: Product > Clean Build Folder (Cmd+Shift+K)
2. Xcode: File > Packages > Reset Package Caches (if SPM types affected)
3. Terminal: `rm -rf ~/Library/Developer/Xcode/DerivedData/WRKT-*`
4. Restart SourceKit daemon: Xcode > Editor > Re-Index File (or restart Xcode)

## Do not act on these errors

Do not add imports, move types, or refactor to "fix" these. Compiler is ground truth. SourceKit is not.
