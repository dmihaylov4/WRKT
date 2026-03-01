import Foundation
import Supabase
import Auth

final class SupabaseClientWrapper: @unchecked Sendable {
    static let shared = SupabaseClientWrapper()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainAuthStorage(),
                    flowType: .implicit
                )
            )
        )
    }
}
