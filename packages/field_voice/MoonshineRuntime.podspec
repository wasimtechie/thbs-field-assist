Pod::Spec.new do |s|
  s.name = 'MoonshineRuntime'
  s.version = '0.1.5'
  s.summary = 'Pinned offline Moonshine Small Streaming and embedded Silero runtime.'
  s.homepage = 'https://github.com/moonshine-ai/moonshine'
  s.license = { :type => 'MIT', :file => '../../docs/licenses/moonshine-LICENSE' }
  s.author = 'Moonshine AI'
  s.source = { :path => '.' }
  s.platform = :ios, '18.0'
  s.vendored_frameworks = 'native/moonshine/apple/Moonshine.xcframework'
  s.libraries = 'c++'
  # Dart FFI resolves these C symbols dynamically. Retain their definitions
  # from the static XCFramework even under the app's dead-strip settings.
  symbols = %w[moonshine_get_version moonshine_load_transcriber_from_files
    moonshine_create_stream moonshine_start_stream moonshine_stop_stream
    moonshine_free_stream moonshine_free_transcriber
    moonshine_transcribe_add_audio_to_stream moonshine_transcribe_stream]
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) ' + symbols.map { |symbol| "-Wl,-u,_#{symbol}" }.join(' ')
  }
end
