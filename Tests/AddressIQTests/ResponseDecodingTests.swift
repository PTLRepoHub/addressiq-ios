import XCTest
@testable import AddressIQ

/// A success body the SDK cannot read is an error, not an empty result.
///
/// `post` used to decode with `(try? …) ?? [:]`, so a 200 carrying a truncated
/// or non-JSON body became an empty dictionary. Callers then read
/// `json["verificationCode"] as? String ?? ""` and returned a *successful*
/// `StartDigitalResult` with empty fields — the caller had no way to tell a
/// real verification from an unreadable response.
final class ResponseDecodingTests: XCTestCase {
    private func decode(_ body: String, status: Int = 200) throws -> [String: Any] {
        try AddressIQ.decodeObject(Data(body.utf8), status: status)
    }

    func testDecodesAJSONObject() throws {
        let json = try decode(#"{"verificationCode":"VER_1","isExisting":false}"#)

        XCTAssertEqual(json["verificationCode"] as? String, "VER_1")
        XCTAssertEqual(json["isExisting"] as? Bool, false)
    }

    func testAnEmptyBodyIsNotAnError() throws {
        // Cancel and other 204-shaped endpoints legitimately return nothing.
        XCTAssertTrue(try AddressIQ.decodeObject(Data(), status: 204).isEmpty)
    }

    func testATruncatedBodyThrowsRatherThanReturningEmpty() {
        XCTAssertThrowsError(try decode(#"{"verificationCode":"VER_1""#)) { error in
            guard let error = error as? AddressIQError else { return XCTFail("wrong error type") }
            XCTAssertEqual(error.code, "INVALID_RESPONSE")
        }
    }

    func testAnHTMLErrorPageThrowsRatherThanReturningEmpty() {
        // What a proxy or captive portal returns with a 200.
        XCTAssertThrowsError(try decode("<html><body>502</body></html>")) { error in
            XCTAssertEqual((error as? AddressIQError)?.code, "INVALID_RESPONSE")
        }
    }

    func testAJSONArrayIsNotAnObject() {
        XCTAssertThrowsError(try decode("[1,2,3]")) { error in
            XCTAssertEqual((error as? AddressIQError)?.code, "INVALID_RESPONSE")
        }
    }

    func testTheSDKVersionHeaderIsBakedNotHardcoded() {
        // Baked from version.txt by scripts/bake-build-config.sh, so it cannot
        // drift from the released artifact the way RN's hardcoded value did.
        XCTAssertFalse(BuildConfig.sdkVersion.isEmpty)
        XCTAssertEqual(AddressIQTransitEvent.sdkVersion, "ios/\(BuildConfig.sdkVersion)")
    }

    func testIdentifyingHeadersAreSetOnARequest() {
        var request = URLRequest(url: URL(string: "https://example.test/x")!)
        request.setIdentifyingHeaders(apiKey: "test-key")

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-sdk-name"), "addressiq-ios")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-sdk-version"), BuildConfig.sdkVersion)
    }
}
