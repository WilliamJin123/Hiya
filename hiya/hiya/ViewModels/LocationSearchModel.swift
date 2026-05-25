import Foundation
import MapKit
import Observation

struct LocationSuggestion: Identifiable, Equatable {
    let title: String
    let subtitle: String
    var id: String { displayString }
    var displayString: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
}

@MainActor
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [LocationSuggestion] = []

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                suggestions = []
                completer.queryFragment = ""
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.prefix(4).map {
            LocationSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in self.suggestions = Array(results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }

    func clear() {
        query = ""
        suggestions = []
    }
}
