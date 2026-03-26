# VOLIA Project

iOS + watchOS fitness app. Swift/SwiftUI, HealthKit, WatchConnectivity, Supabase.

## Structure
- `Core/` — models, services, utilities
- `Features/` — feature modules (Social, Health, Planner, Home, etc.)
- `DesignSystem/` — `DS.Theme`, `DS.Semantic`, `DS.Palette`, `ChamferedRectangle`
- `WRKT Watch Watch App/` — watchOS target (separate singletons, not shared)
- `Shared/` — models shared between iOS and Watch targets

## Dependencies
- `@Environment(\.dependencies)` -> `AppDependencies` (injected on iOS)
- Watch singletons: `WatchHealthKitManager.shared`, `VirtualRunManager.shared`, `WatchConnectivityManager.shared`

## Response Formatting
- No emojis in any output (code comments, explanations, summaries)
- No em dashes — use a colon instead

## UI Conventions
- Stat columns: `HStack(spacing: 0)` with each column `.frame(maxWidth: .infinity)` + 1pt `Rectangle().fill(DS.Semantic.border)` dividers
- Duration in compact/hero UI: drop seconds when >= 1h — show `h:mm` not `h:mm:ss`
- Design tokens always: `DS.Semantic.textPrimary/Secondary`, `DS.Semantic.brand`, `DS.Semantic.card`, `DS.Semantic.border`

## Key Gotchas (see memory files for full detail)
- WCSession delegates are `nonisolated` — dispatch to `@MainActor` via `Task { @MainActor in }`
- `VirtualRunManager` is `@Observable @MainActor` — all WCSession calls need MainActor dispatch
- iPhone→Watch WCSession message key: `"type"`. Watch→iPhone key: `"messageType"`. Do not unify.
- `HKWorkoutRoute` queries: always pass `sortDescriptors: nil` — sort silently returns empty on some OS versions
- `CLLocationManager.desiredAccuracy` MUST stay `kCLLocationAccuracyBest` — do not lower for energy savings
