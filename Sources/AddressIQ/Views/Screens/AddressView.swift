import SwiftUI
import CoreLocation
import MapKit

/// Address capture for the Collect UI.
///
/// Map flow (when a Google Maps key is configured): current location / Places
/// Autocomplete → MapKit map with a centre pin → auto-derived (read-only)
/// formatted address → Street View pin-confirm where coverage exists. Falls back
/// to GPS + a manual formatted-address field when no key is available.
@available(iOS 15.0, *)
struct AddressView: View {
    let initial: AddressDraft
    /// Google Maps API key (enables the map flow). When nil → manual entry.
    let googleMapsApiKey: String?
    let onNext: (AddressDraft) -> Void
    let onCancel: () -> Void

    @Environment(\.addressIQTheme) private var theme

    @State private var region: MKCoordinateRegion
    @State private var formatted: String
    @State private var placeId: String?
    @State private var hasPoint: Bool
    @State private var loading = false
    @State private var resolving = false
    @State private var query = ""
    @State private var suggestions: [PlaceSuggestion] = []
    @State private var showStreetView = false
    @State private var svPanoId: String?
    @State private var locationDelegate: LocationOneShot?
    @State private var geocodeTask: Task<Void, Never>?
    @State private var suppressNextGeocode = false

    private let sessionToken = UUID().uuidString

    init(initial: AddressDraft, googleMapsApiKey: String?, onNext: @escaping (AddressDraft) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.googleMapsApiKey = googleMapsApiKey
        self.onNext = onNext
        self.onCancel = onCancel
        let center = CLLocationCoordinate2D(latitude: initial.lat ?? 6.5244, longitude: initial.lon ?? 3.3792)
        _region = State(initialValue: MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
        _formatted = State(initialValue: initial.formattedAddress ?? "")
        _placeId = State(initialValue: initial.placeId)
        _hasPoint = State(initialValue: initial.lat != nil && initial.lon != nil)
    }

    private var mapsKey: String? {
        guard let k = googleMapsApiKey, !k.isEmpty else { return nil }
        return k
    }

    private var centerKey: String {
        String(format: "%.5f,%.5f", region.center.latitude, region.center.longitude)
    }

    private var canContinue: Bool { hasPoint && !formatted.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScreenScaffold(
            title: "Confirm your address",
            subtitle: "Search for your address or drop a pin on the map. We'll use this to verify where you live.",
            step: 0,
            totalSteps: 3,
            onClose: onCancel,
            content: { content },
            footer: {
                AddressIQButton(
                    title: resolving ? "Loading…" : "Continue",
                    action: onContinue,
                    enabled: canContinue && !resolving
                )
            }
        )
        .fullScreenCover(isPresented: $showStreetView) {
            if let key = mapsKey {
                StreetViewScreen(
                    apiKey: key,
                    lat: region.center.latitude,
                    lon: region.center.longitude,
                    panoId: svPanoId,
                    onConfirm: { pano in svPanoId = pano; showStreetView = false; finish() },
                    onBack: { showStreetView = false },
                    onCancel: onCancel
                )
                .environment(\.addressIQTheme, theme)
            }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mapsKey != nil {
                searchBar
                if !suggestions.isEmpty { suggestionList }
            }
            mapOrLoading
            Button(action: captureLocation) {
                HStack(spacing: 6) {
                    Image(systemName: "location.north.fill").font(.system(size: 12))
                    Text("Use my current location").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(theme.primary)
            }
            Text("Formatted address").font(.system(size: 14, weight: .semibold)).foregroundColor(theme.text)
            addressField
            Text("The next screen captures property details (house number, building color, directions).")
                .font(.system(size: 12)).foregroundColor(theme.textSecondary)
        }
        .onAppear { if !hasPoint { captureLocation() } }
        .onChange(of: centerKey) { _ in scheduleReverseGeocode() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(theme.textSecondary)
            TextField("Search your address", text: $query)
                .font(.system(size: 15)).foregroundColor(theme.text)
                .onChange(of: query) { _ in onSearchChange() }
        }
        .padding(.horizontal, 12).frame(height: 46)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { s in
                Button(action: { pickSuggestion(s) }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.primaryText).font(.system(size: 14, weight: .semibold)).foregroundColor(theme.text)
                        if let sub = s.secondaryText {
                            Text(sub).font(.system(size: 12)).foregroundColor(theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
            }
        }
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var mapOrLoading: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().tint(theme.primary)
                Text("Reading GPS…").font(.system(size: 13)).foregroundColor(theme.textSecondary)
            }
            .frame(maxWidth: .infinity).frame(height: 120)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: theme.borderRadiusLg).stroke(theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: theme.borderRadiusLg))
        } else {
            ZStack {
                Map(coordinateRegion: $region)
                    .frame(height: 220)
                Image(systemName: "mappin")
                    .font(.system(size: 30))
                    .foregroundColor(theme.primary)
                    .offset(y: -15)
            }
            .overlay(RoundedRectangle(cornerRadius: theme.borderRadiusLg).stroke(theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: theme.borderRadiusLg))
        }
    }

    @ViewBuilder private var addressField: some View {
        if mapsKey != nil {
            // Auto-derived, read-only.
            HStack {
                if resolving {
                    ProgressView().tint(theme.primary)
                } else {
                    Text(formatted.isEmpty ? "Move the pin or search to set your address." : formatted)
                        .font(.system(size: 15)).foregroundColor(theme.text)
                }
                Spacer()
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(theme.surfaceSecondary)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            // No key → manual entry fallback.
            TextEditor(text: $formatted)
                .font(.system(size: 15)).foregroundColor(theme.inputText)
                .hiddenScrollBackground().background(theme.inputBg)
                .frame(minHeight: 70).padding(.horizontal, 8)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inputBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // ── Actions ──

    private func onContinue() {
        guard hasPoint else { return }
        if let key = mapsKey {
            resolving = true
            Task {
                let cov = await MapsClient(apiKey: key).streetViewCoverage(region.center.latitude, region.center.longitude)
                await MainActor.run {
                    resolving = false
                    if cov.available {
                        svPanoId = cov.panoId
                        showStreetView = true
                    } else {
                        finish()
                    }
                }
            }
        } else {
            finish()
        }
    }

    private func finish() {
        var draft = initial
        draft.lat = region.center.latitude
        draft.lon = region.center.longitude
        draft.formattedAddress = formatted.trimmingCharacters(in: .whitespaces)
        draft.placeId = placeId
        draft.streetviewPanoId = svPanoId
        onNext(draft)
    }

    private func onSearchChange() {
        guard let key = mapsKey, query.trimmingCharacters(in: .whitespaces).count >= 3 else {
            suggestions = []
            return
        }
        Task {
            let out = await MapsClient(apiKey: key).autocomplete(query, sessionToken: sessionToken)
            await MainActor.run { suggestions = out }
        }
    }

    private func pickSuggestion(_ s: PlaceSuggestion) {
        query = ""
        suggestions = []
        guard let key = mapsKey else { return }
        resolving = true
        Task {
            let place = await MapsClient(apiKey: key).placeDetails(s.id, sessionToken: sessionToken)
            await MainActor.run {
                resolving = false
                if let place = place {
                    suppressNextGeocode = true
                    placeId = s.id
                    formatted = place.formattedAddress
                    hasPoint = true
                    region.center = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
                }
            }
        }
    }

    private func scheduleReverseGeocode() {
        hasPoint = true
        if suppressNextGeocode { suppressNextGeocode = false; return }
        guard let key = mapsKey else { return }
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await MainActor.run { resolving = true }
            let addr = await MapsClient(apiKey: key).reverseGeocode(region.center.latitude, region.center.longitude)
            if Task.isCancelled { return }
            await MainActor.run {
                resolving = false
                if let addr = addr { formatted = addr }
            }
        }
    }

    private func captureLocation() {
        loading = true
        let delegate = LocationOneShot { loc in
            DispatchQueue.main.async {
                if let loc = loc {
                    self.suppressNextGeocode = false
                    self.region.center = loc.coordinate
                    self.hasPoint = true
                }
                self.loading = false
                self.locationDelegate = nil
            }
        }
        locationDelegate = delegate
        delegate.start()
    }
}

private final class LocationOneShot: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let onComplete: (CLLocation?) -> Void
    private var done = false

    init(onComplete: @escaping (CLLocation?) -> Void) {
        self.onComplete = onComplete
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !done, let loc = locations.last else { return }
        done = true
        onComplete(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !done else { return }
        done = true
        onComplete(nil)
    }
}
