import Foundation

struct CutLikesListModel: Equatable {
    struct Person: Equatable, Identifiable {
        var id: UUID
        var name: String
        var handle: String?
        var initials: String
        var avatarURL: String?
    }
    enum Content: Equatable {
        case loading
        case empty
        case failed(String)
        case people([Person])
    }
    var content: Content
    var inlineError: String?
}

enum CutLikesListLogic {
    static func model(people: [CutSocialPersonFacts]?, error: String?) -> CutLikesListModel {
        guard let people else { return .init(content: error.map(CutLikesListModel.Content.failed) ?? .loading) }
        guard !people.isEmpty else { return .init(content: error.map(CutLikesListModel.Content.failed) ?? .empty) }
        return .init(content: .people(people.map {
            .init(id: $0.id, name: CutSocialPeopleLogic.name($0), handle: CutSocialPeopleLogic.handleLine($0),
                  initials: CutSocialLogic.initials($0.displayName ?? $0.username), avatarURL: $0.avatarURL)
        }), inlineError: error)
    }
}
