import Foundation

/// A Places Autocomplete suggestion.
struct PlaceSuggestion: Identifiable {
    let id: String // placeId
    let primaryText: String
    let secondaryText: String?
}

/// A place resolved to a canonical formatted address + coordinates.
struct ResolvedPlace {
    let formattedAddress: String
    let lat: Double
    let lon: Double
}

/// Street View coverage result from the (free) metadata endpoint.
struct StreetViewCoverage {
    let available: Bool
    let panoId: String?
}

/// Google Maps Platform REST clients for the Collect UI map flow.
///
/// Pure `URLSession` — **no GoogleMaps SDK dependency** (the base map uses
/// MapKit, Street View uses a WKWebView). Every call is best-effort: on any
/// error it resolves to an empty/nil result so the address step degrades to
/// manual entry rather than throwing.
@available(iOS 15.0, *)
struct MapsClient {
    let apiKey: String

    private static let placesBase = "https://places.googleapis.com/v1"
    private static let mapsBase = "https://maps.googleapis.com/maps/api"

    /// Places Autocomplete (New) — POST places:autocomplete.
    func autocomplete(_ input: String, sessionToken: String?) async -> [PlaceSuggestion] {
        guard !input.isEmpty, !apiKey.isEmpty,
              let url = URL(string: "\(Self.placesBase)/places:autocomplete") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        var body: [String: Any] = ["input": input]
        if let t = sessionToken { body["sessionToken"] = t }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let suggestions = json["suggestions"] as? [[String: Any]] else { return [] }
        return suggestions.compactMap { s in
            guard let p = s["placePrediction"] as? [String: Any],
                  let id = p["placeId"] as? String else { return nil }
            let sf = p["structuredFormat"] as? [String: Any]
            let main = (sf?["mainText"] as? [String: Any])?["text"] as? String
            let sec = (sf?["secondaryText"] as? [String: Any])?["text"] as? String
            let text = (p["text"] as? [String: Any])?["text"] as? String
            return PlaceSuggestion(id: id, primaryText: main ?? text ?? "", secondaryText: sec)
        }
    }

    /// Place Details (New) — resolve a placeId to formatted address + coordinates.
    func placeDetails(_ placeId: String, sessionToken: String?) async -> ResolvedPlace? {
        guard !placeId.isEmpty, !apiKey.isEmpty,
              var comps = URLComponents(string: "\(Self.placesBase)/places/\(placeId)") else { return nil }
        if let t = sessionToken { comps.queryItems = [URLQueryItem(name: "sessionToken", value: t)] }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("formattedAddress,location", forHTTPHeaderField: "X-Goog-FieldMask")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loc = json["location"] as? [String: Any],
              let lat = loc["latitude"] as? Double, let lon = loc["longitude"] as? Double else { return nil }
        return ResolvedPlace(formattedAddress: json["formattedAddress"] as? String ?? "", lat: lat, lon: lon)
    }

    /// Reverse-geocode a coordinate to Google's canonical formatted address.
    func reverseGeocode(_ lat: Double, _ lon: Double) async -> String? {
        guard !apiKey.isEmpty,
              let url = URL(string: "\(Self.mapsBase)/geocode/json?latlng=\(lat),\(lon)&key=\(apiKey)") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? String) == "OK",
              let results = json["results"] as? [[String: Any]] else { return nil }
        return results.first?["formatted_address"] as? String
    }

    /// Street View Image Metadata — free, no quota. Gates the Street View step.
    func streetViewCoverage(_ lat: Double, _ lon: Double) async -> StreetViewCoverage {
        guard !apiKey.isEmpty,
              let url = URL(string: "\(Self.mapsBase)/streetview/metadata?location=\(lat),\(lon)&key=\(apiKey)")
        else { return StreetViewCoverage(available: false, panoId: nil) }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? String) == "OK"
        else { return StreetViewCoverage(available: false, panoId: nil) }
        return StreetViewCoverage(available: true, panoId: json["pano_id"] as? String)
    }
}
