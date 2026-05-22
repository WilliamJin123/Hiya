import Foundation

enum SupabaseConfig {
    static let url = URL(string: "https://znvrlyjmbcqqkhgctcop.supabase.co")!
    // anon key is safe to ship — RLS enforces per-user access.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpudnJseWptYmNxcWtoZ2N0Y29wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0MTQ0MTYsImV4cCI6MjA5NDk5MDQxNn0.JNlIV_1k3cr_T6OxrfrMpYDFIyVErSBbEyZdlOKd-rA"
}
