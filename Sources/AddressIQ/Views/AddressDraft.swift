import Foundation

/// In-flight address being collected through the verify flow. Held in
/// `@State` on the orchestrator so SwiftUI manages the form state.
public struct AddressDraft: Equatable {
    public var lat: Double?
    public var lon: Double?
    public var formattedAddress: String?
    public var propertyNumber: String?
    public var streetName: String?
    public var buildingColor: String?
    public var directions: String?
    // Map-flow fields (Places autocomplete + Street View pin-confirm).
    public var placeId: String?
    public var streetviewPanoId: String?
    public var streetviewHeading: Double?

    public init(
        lat: Double? = nil,
        lon: Double? = nil,
        formattedAddress: String? = nil,
        propertyNumber: String? = nil,
        streetName: String? = nil,
        buildingColor: String? = nil,
        directions: String? = nil,
        placeId: String? = nil,
        streetviewPanoId: String? = nil,
        streetviewHeading: Double? = nil
    ) {
        self.lat = lat
        self.lon = lon
        self.formattedAddress = formattedAddress
        self.propertyNumber = propertyNumber
        self.streetName = streetName
        self.buildingColor = buildingColor
        self.directions = directions
        self.placeId = placeId
        self.streetviewPanoId = streetviewPanoId
        self.streetviewHeading = streetviewHeading
    }
}
