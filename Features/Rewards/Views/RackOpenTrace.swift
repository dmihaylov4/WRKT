// Features/Rewards/Views/RackOpenTrace.swift
//
// Open-time instrumentation for the rack scene. RackOpenTrace keeps named marks from the host's
// first task to the scene's first frame (DEBUG builds only; each mark is also a signpost event on
// the Barbell signposter, so Instruments shows it beside the existing intervals). RackWorkCounters
// counts the expensive work (face images drawn, panoramas built, thumbnails rendered) so tests can
// guard the open's cost by counting work instead of timing it. Nothing here runs per frame.

import Combine
import Foundation
import os
import QuartzCore
import RealityKit
import SwiftUI

/// The expensive steps of opening the rack, counted by RackWorkCounters.
nonisolated enum RackWork: String, CaseIterable, Sendable {
    /// A lathe face's colour, normal and roughness images drawn with CoreGraphics.
    case faceImagesDrawn
    /// A lathe face's images read back from the disk cache instead of drawn.
    case faceImagesReadFromDisk
    /// A lathe face's three textures uploaded to RealityKit.
    case faceTexturesUploaded
    /// The studio .hdr decoded and turned into a panorama.
    case studioPanoramasBuilt
    /// The studio panorama read back from the disk cache instead of decoded.
    case studioPanoramasReadFromDisk
    /// The procedural rack room panorama computed.
    case roomPanoramasBuilt
    /// A plate thumbnail rendered with RealityKit (PlateSnapshotService).
    case thumbnailsRendered
    /// A rack rail sprite or lifted face rendered with RealityKit (RackRailSpriteService).
    case railSpritesRendered
    /// A lathe plate built before its face was ready, with its body finish on the face.
    case facePlaceholdersShown
    /// A ready face put on plates built with the placeholder.
    case faceSwaps
    /// A face dropped from the in-memory cache (LatheFaceCache).
    case faceTexturesEvicted
    /// SwiftUI body evaluations (DEBUG builds): the rack host, the rail screen, its plate row
    /// and the plate pictures in it. A drag or throw should cause a few, not one per frame.
    case hostBodies
    case railScreenBodies
    case railRowBodies
    case railPictureBodies
    /// The rack scene's frame updates, and the main-thread microseconds they took (DEBUG builds).
    case sceneFrameUpdates
    case sceneFrameUpdateMicros
}

/// Process-wide counts of RackWork. One locked increment per expensive call.
nonisolated enum RackWorkCounters {
    private static let counts = OSAllocatedUnfairLock<[RackWork: Int]>(initialState: [:])

    /// A DEBUG-only count, usable inside a view body as `let _ = RackWorkCounters.debugTick(.x)`.
    @discardableResult
    static func debugTick(_ work: RackWork) -> Bool {
        #if DEBUG
        add(work)
        #endif
        return true
    }

    static func add(_ work: RackWork, _ amount: Int = 1) {
        counts.withLock { $0[work, default: 0] += amount }
    }

    static func count(_ work: RackWork) -> Int {
        counts.withLock { $0[work] ?? 0 }
    }

    static func snapshot() -> [RackWork: Int] {
        counts.withLock { $0 }
    }
}

/// Timestamps of the most recent rack open (DEBUG builds; Release keeps only the signposts).
@MainActor
enum RackOpenTrace {
    struct Mark: Sendable, Equatable {
        let name: String
        let time: CFTimeInterval
    }

    private(set) static var marks: [Mark] = []
    private static var frameSubscription: EventSubscription?
    private static let maximumMarks = 64

    /// Starts a new open: drops the previous open's marks.
    static func begin(_ name: StaticString) {
        #if DEBUG
        marks.removeAll(keepingCapacity: true)
        frameSubscription?.cancel()
        frameSubscription = nil
        #endif
        mark(name)
    }

    static func mark(_ name: StaticString) {
        barbellSignposter.emitEvent(name)
        #if DEBUG
        if marks.count >= maximumMarks { marks.removeFirst() }
        marks.append(Mark(name: "\(name)", time: CACurrentMediaTime()))
        #endif
    }

    /// The time of the latest mark with this name, if any.
    static func time(of name: String) -> CFTimeInterval? {
        marks.last { $0.name == name }?.time
    }

    private static var sceneFrameSubscriptions: [UUID: any Cancellable] = [:]

    /// Marks `name` on the scene's next update, then stops listening (one event, not per frame).
    /// For work started outside make (a tray load, a release).
    static func markNextFrame(_ name: StaticString, scene: RealityKit.Scene?) {
        #if DEBUG
        guard let scene else { return }
        let id = UUID()
        sceneFrameSubscriptions[id] = scene.subscribe(to: SceneEvents.Update.self) { _ in
            MainActor.assumeIsolated {
                mark(name)
                sceneFrameSubscriptions.removeValue(forKey: id)?.cancel()
            }
        }
        #endif
    }

    /// Marks `name` on the scene's next update, then stops listening (one event, not per frame).
    static func markNextFrame(_ name: StaticString, content: RealityViewCameraContent) {
        #if DEBUG
        frameSubscription?.cancel()
        frameSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
            MainActor.assumeIsolated {
                mark(name)
                frameSubscription?.cancel()
                frameSubscription = nil
            }
        }
        #endif
    }
}
