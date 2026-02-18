import Foundation

/// Base protocol for all ViewModels in the app
/// Provides common lifecycle and state management patterns
@MainActor
protocol ViewModelProtocol: AnyObject, Observable {
    /// Loading state indicator
    var isLoading: Bool { get set }

    /// Error state for user-facing errors
    var error: UserFriendlyError? { get set }

    /// Lifecycle method called when view appears
    func onAppear() async

    /// Lifecycle method called when view disappears
    func onDisappear() async

    /// Refresh data from source
    func refresh() async
}

// MARK: - Default Implementations

extension ViewModelProtocol {
    /// Default implementation does nothing
    func onAppear() async {
        // Override in subclass if needed
    }

    /// Default implementation does nothing
    func onDisappear() async {
        // Override in subclass if needed
    }

    /// Default implementation does nothing
    func refresh() async {
        // Override in subclass if needed
    }
}

// MARK: - Common ViewModel State

/// Common state properties that many ViewModels share
struct ViewModelState {
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var error: UserFriendlyError? = nil
}
