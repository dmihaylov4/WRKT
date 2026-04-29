//
//  SharedProgramStructure.swift
//  WRKT
//
//  Versioned wire payload for shared workout programs.
//

import Foundation

struct SharedProgramStructure: Codable, Sendable, Equatable {
    enum DecodingError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    struct CreatorAttribution: Codable, Sendable, Equatable {
        let userID: String
        let username: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case username
            case displayName = "display_name"
        }
    }

    struct Block: Codable, Sendable, Equatable {
        let dayName: String
        let isRestDay: Bool
        let order: Int
        let exercises: [Exercise]
    }

    struct Exercise: Codable, Sendable, Equatable {
        let exerciseID: String
        let exerciseName: String
        let sets: Int
        let reps: Int
        let progressionStrategy: Progression
        let order: Int

        enum CodingKeys: String, CodingKey {
            case exerciseID = "exerciseID"
            case exerciseName
            case sets
            case reps
            case progressionStrategy
            case order
        }
    }

    enum Progression: Codable, Sendable, Equatable {
        case linear(increment: Double)
        case percentage(factor: Double)
        case autoregulated
        case `static`

        enum CodingKeys: String, CodingKey {
            case type
            case increment
            case factor
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = (try? container.decode(String.self, forKey: .type)) ?? "static"

            switch type {
            case "linear":
                self = .linear(increment: (try? container.decode(Double.self, forKey: .increment)) ?? 2.5)
            case "percentage":
                self = .percentage(factor: (try? container.decode(Double.self, forKey: .factor)) ?? 1.0)
            case "autoregulated":
                self = .autoregulated
            case "static":
                self = .static
            default:
                self = .static
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .linear(let increment):
                try container.encode("linear", forKey: .type)
                try container.encode(increment, forKey: .increment)
            case .percentage(let factor):
                try container.encode("percentage", forKey: .type)
                try container.encode(factor, forKey: .factor)
            case .autoregulated:
                try container.encode("autoregulated", forKey: .type)
            case .static:
                try container.encode("static", forKey: .type)
            }
        }
    }

    let version: Int
    let creator: CreatorAttribution?
    let planBlocks: [Block]

    init(version: Int = 1, creator: CreatorAttribution? = nil, planBlocks: [Block]) {
        self.version = version
        self.creator = creator
        self.planBlocks = planBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.unsupportedVersion(version)
        }

        self.version = version
        self.creator = try container.decodeIfPresent(CreatorAttribution.self, forKey: .creator)
        self.planBlocks = try container.decode([Block].self, forKey: .planBlocks)
    }
}
