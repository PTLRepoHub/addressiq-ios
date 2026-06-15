import SwiftUI
import WebKit

/// Street View pin-confirm step. Shown only when the Street View metadata check
/// found coverage at the picked point. iOS has a native `GMSPanoramaView`, but
/// that needs the GoogleMaps SDK; to stay dependency-free we embed Maps JS
/// Street View in a `WKWebView` (same approach as the React Native SDK). The
/// user frames their building and confirms; we record the pano id.
@available(iOS 15.0, *)
struct StreetViewScreen: View {
    let apiKey: String
    let lat: Double
    let lon: Double
    let panoId: String?
    let onConfirm: (_ panoId: String?) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    @Environment(\.addressIQTheme) private var theme

    var body: some View {
        ScreenScaffold(
            title: "Confirm your building",
            subtitle: "Drag the view to frame your building, then confirm.",
            onClose: onCancel,
            content: {
                StreetViewWeb(apiKey: apiKey, lat: lat, lon: lon)
                    .frame(height: 320)
                    .overlay(RoundedRectangle(cornerRadius: theme.borderRadiusLg).stroke(theme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadiusLg))
            },
            footer: {
                HStack(spacing: 12) {
                    AddressIQButton(title: "Back", action: onBack, variant: .secondary)
                    AddressIQButton(title: "Confirm", action: { onConfirm(panoId) })
                }
            }
        )
    }
}

@available(iOS 15.0, *)
private struct StreetViewWeb: UIViewRepresentable {
    let apiKey: String
    let lat: Double
    let lon: Double

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private var html: String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body,#pano{height:100%;margin:0;padding:0}</style></head>
        <body><div id="pano"></div>
        <script>
        function init(){
          new google.maps.StreetViewPanorama(document.getElementById('pano'), {
            position: {lat: \(lat), lng: \(lon)}, pov: {heading: 0, pitch: 0}, zoom: 1,
            addressControl: false, fullscreenControl: false, motionTracking: false, motionTrackingControl: false
          });
        }
        </script>
        <script async src="https://maps.googleapis.com/maps/api/js?key=\(apiKey)&callback=init"></script>
        </body></html>
        """
    }
}
