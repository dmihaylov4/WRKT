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
                    storage: UserDefaultsStorage(),
                    flowType: .implicit
                )
                // Note: Realtime is enabled by default in SupabaseClient
                // No additional configuration needed
            )
        )
    }
}

// Custom storage implementation using UserDefaults
final class UserDefaultsStorage: @unchecked Sendable, AuthLocalStorage {
    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: key)
    }

    func retrieve(key: String) throws -> Data? {
        let data = UserDefaults.standard.data(forKey: key)
        if data != nil {
        } else {
        }
        return data
    }

    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
