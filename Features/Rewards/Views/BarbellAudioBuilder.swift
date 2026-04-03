// Features/Rewards/Views/BarbellAudioBuilder.swift
import RealityKit
import UIKit

// MARK: - PlateAudioCategory extension
// Base enum (cases) is defined in BarbellEntityBuilder.swift.
// All logic is here so audio concerns stay in one file.

extension PlateAudioCategory {

    static func from(tierID: Int) -> PlateAudioCategory {
        switch tierID {
        case 0, 1: return .iron
        case 2:    return .rubber
        case 3, 6: return .brass
        case 7:    return .starter
        default:   return .iron
        }
    }

    var clinkSoundName: String {
        switch self {
        case .iron:    return "plate_clink_iron"
        case .rubber:  return "plate_thud_rubber"
        case .brass:   return "plate_clink_brass"
        case .starter: return "plate_thud_rubber"
        }
    }

    var dropSoundName: String {
        switch self {
        case .iron:    return "plate_drop_iron"
        case .rubber:  return "plate_drop_rubber"
        case .brass:   return "plate_drop_brass"
        case .starter: return "plate_drop_rubber"
        }
    }

    /// Physics material tuned per plate material type.
    /// Iron: moderate bounce, medium friction.
    /// Rubber bumper: low bounce, high friction (grips the floor).
    /// Brass: slightly more bounce than iron due to density.
    var physicsMaterial: PhysicsMaterialResource {
        switch self {
        case .iron:    return .generate(friction: 0.70, restitution: 0.30)
        case .rubber:  return .generate(friction: 0.92, restitution: 0.08)
        case .brass:   return .generate(friction: 0.65, restitution: 0.38)
        case .starter: return .generate(friction: 0.85, restitution: 0.12)
        }
    }
}

// MARK: - Audio resource cache

// Process-level cache -- resources are loaded once and reused across view instances
// and mode switches. nonisolated(unsafe) because writes are guarded by call-site
// sequencing (all loads happen in .task{} before gesture handlers can fire).
private nonisolated(unsafe) var audioResourceCache: [String: AudioFileResource] = [:]

func loadAudioResource(named name: String) -> AudioFileResource? {
    if let cached = audioResourceCache[name] { return cached }
    guard let resource = try? AudioFileResource.load(named: name, in: .main,
                                                      configuration: .init()) else { return nil }
    audioResourceCache[name] = resource
    return resource
}

// MARK: - Spatial audio helpers

/// Attaches a SpatialAudioComponent to the entity. Must be called before playAudio().
/// Called from makePlateEntity so every plate entity is automatically a spatial emitter.
func attachSpatialAudio(to entity: Entity, category: PlateAudioCategory) {
    var audio = SpatialAudioComponent(gain: -6)
    audio.directivity = .beam(focus: 0.5)
    entity.components.set(audio)
}

/// Plays the rack/clink sound at the entity's world position.
func playClinkSound(on entity: Entity, category: PlateAudioCategory) {
    guard let resource = loadAudioResource(named: category.clinkSoundName) else { return }
    entity.playAudio(resource)
}

/// Plays the floor-drop sound at the entity's world position.
func playDropSound(on entity: Entity, category: PlateAudioCategory) {
    guard let resource = loadAudioResource(named: category.dropSoundName) else { return }
    entity.playAudio(resource)
}

// MARK: - Haptic vocabulary
//
// Typed haptic functions keyed to plate material category.
// Do not use a single undifferentiated haptic -- iron racking onto steel should feel
// different from rubber bumpers settling on a floor.

/// Fires on successful rack (plate lands on bar).
/// Iron/brass: rigid impact (hard metal-on-metal).
/// Rubber/starter: soft impact (rubber damping).
func playRackHaptic(category: PlateAudioCategory) {
    switch category {
    case .iron, .brass:
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    case .rubber, .starter:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

/// Fires once when a dragged plate enters the bar snap zone.
/// Light selection tick -- tells the user "you're in range" without committing.
func playSnapZoneEntryHaptic() {
    UISelectionFeedbackGenerator().selectionChanged()
}

/// Fires when a plate lands on the floor after unracking.
/// Iron/brass: heavy drop. Rubber: medium (absorbs impact).
func playDropHaptic(category: PlateAudioCategory) {
    switch category {
    case .iron, .brass:
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case .rubber, .starter:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
