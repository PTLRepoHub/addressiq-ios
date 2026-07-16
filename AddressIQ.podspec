Pod::Spec.new do |s|
  s.name             = 'AddressIQ'
  # Version is injected by CI from the release git tag (POD_VERSION=1.2.3);
  # falls back to 0.0.0 for local `pod lib lint`. See release.yml.
  s.version          = ENV['POD_VERSION'] || '0.0.0'
  s.summary          = 'AddressIQ address collection + verification SDK for iOS.'
  s.description      = <<-DESC
    Native iOS SDK for AddressIQ — same behavioral contract as the React
    Native and Flutter SDKs. Address collection plus physical/combined
    verification lifecycle.
  DESC
  s.homepage         = 'https://addressiqpro.com'
  s.license          = { :type => 'Proprietary', :text => 'Copyright AddressIQ. All rights reserved.' }
  s.author           = { 'AddressIQ' => 'sdk@addressiqpro.com' }
  s.source           = {
    :git => 'https://github.com/PTLRepoHub/addressiq-ios.git',
    :tag => "v#{s.version}"
  }

  # Mirrors Package.swift: iOS 13 floor (core); the SwiftUI UI is iOS 15+.
  s.ios.deployment_target = '13.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/AddressIQ/**/*.swift'
  s.frameworks       = 'Foundation', 'UIKit', 'SwiftUI', 'CoreLocation'

  # source_files globs in Generated/**/*.pb.swift, which `import SwiftProtobuf`.
  # Mirrors Package.swift's swift-protobuf dependency. Without this the pod
  # does not compile (unnoticed until now because CI only ran `--quick` lint).
  s.dependency 'SwiftProtobuf', '~> 1.38'

  # No resource bundle: the collect/verify widget is loaded from the SRI-pinned
  # CDN, not shipped inside the pod.
end
