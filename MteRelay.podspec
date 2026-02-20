Pod::Spec.new do |s|
  s.name         = 'MteRelay'
  s.version      = '4.5.1'
  s.summary      = 'Eclypses MTE Relay Client for iOS'
  s.description  = 'Swift wrapper and client for the Eclypses MTE Relay, including the precompiled Mte static library.'
  s.homepage     = 'https://github.com/Eclypses/mte-relay-client-ios'
  s.license      = { :type => 'MIT' }
  s.authors      = { 'Eclypses' => 'support@eclypses.com' }

  s.platform     = :ios, '16.0'
  s.swift_version = '5.9'

  s.source = { :git => "https://github.com/Eclypses/mte-relay-client-ios.git", :tag => "v4.5.1" }

  # All your Swift source files and internal C header files are listed here.
  s.source_files = [
  'Classes/**/*.swift',
  'Classes/Mte/include/*.h']

  s.vendored_frameworks = 'Classes/Mte/mte.xcframework'
  
  s.preserve_paths = 'Classes/Mte/include', 'Classes/Mte/mte.xcframework'

  s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
      
      'HEADER_SEARCH_PATHS' => '$(inherited) ' \
                               '"${PODS_TARGET_SRCROOT}/Classes/Mte/include" ' \
                               '"${BUILT_PRODUCTS_DIR}/${TARGET_NAME}.framework/Headers"',

      'OTHER_LDFLAGS' => '-ObjC',
    }
end
