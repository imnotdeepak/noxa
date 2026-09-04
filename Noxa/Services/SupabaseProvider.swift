import Foundation
import Supabase

enum SupabaseProvider {
    static let projectURL = URL(string: "https://ckwikbybjgydfcqpnfyo.supabase.co")!
    static let publishableKey = "sb_publishable_ULdLuWwQ8FmFSdq4wyE-cQ_NphV5aIN"
    static let authCallbackURL = URL(string: "noxa://auth-callback")!

    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: publishableKey,
        options: .init(auth: .init(redirectToURL: authCallbackURL))
    )
}
