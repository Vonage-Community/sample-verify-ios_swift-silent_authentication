import Foundation

enum Configuration {
    static var baseURL: String {
        guard let url = Bundle.main.infoDictionary?["BASE_URL"] as? String, !url.isEmpty else {
            return "http://localhost:4000"
        }
        return url
    }
}
