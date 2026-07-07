#!/usr/bin/env ruby
# Creates SilentAuthDemo.xcodeproj using the xcodeproj gem.
# Run from the repo root: ruby scripts/create_xcodeproj.rb
# Requires: gem install xcodeproj --user-install

require 'xcodeproj'

REPO_ROOT   = File.expand_path('..', __dir__)
IOS_DIR     = File.join(REPO_ROOT, 'ios')
PROJ_PATH   = File.join(IOS_DIR, 'SilentAuthDemo.xcodeproj')
APP_DIR     = File.join(IOS_DIR, 'SilentAuthDemo')
TESTS_DIR   = File.join(IOS_DIR, 'SilentAuthDemoTests')
XCCONFIG    = 'Config.xcconfig'

# ── Create project ──────────────────────────────────────────────────────────
project = Xcodeproj::Project.new(PROJ_PATH)

# ── App target ──────────────────────────────────────────────────────────────
app_target = project.new_target(:application, 'SilentAuthDemo', :ios, '16.0')

app_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'     => 'com.vonage.SilentAuthDemo',
    'SWIFT_VERSION'                 => '5.9',
    'TARGETED_DEVICE_FAMILY'        => '1,2',       # iPhone + iPad
    'INFOPLIST_FILE'                => 'SilentAuthDemo/Info.plist',
    'CODE_SIGN_STYLE'               => 'Automatic',
    'DEVELOPMENT_TEAM'              => '',
    'SWIFT_EMIT_LOC_STRINGS'        => 'YES',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'BASE_XCCONFIG'                 => '$(PROJECT_DIR)/Config.xcconfig',
  )
  # Apply the xcconfig to each build configuration
  xcconfig_ref = project.new_file(XCCONFIG)
  config.base_configuration_reference = xcconfig_ref unless config.base_configuration_reference
end

# ── Test target ──────────────────────────────────────────────────────────────
test_target = project.new_target(:unit_test_bundle, 'SilentAuthDemoTests', :ios, '16.0')

test_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'  => 'com.vonage.SilentAuthDemoTests',
    'SWIFT_VERSION'              => '5.9',
    'TARGETED_DEVICE_FAMILY'     => '1,2',
    'GENERATE_INFOPLIST_FILE'    => 'YES',
    'TEST_HOST'                  => '$(BUILT_PRODUCTS_DIR)/SilentAuthDemo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SilentAuthDemo',
    'BUNDLE_LOADER'              => '$(TEST_HOST)',
  )
end

# Wire test target → app target
test_target.add_dependency(app_target)

# ── File groups ──────────────────────────────────────────────────────────────
main_group = project.main_group

app_group   = main_group.new_group('SilentAuthDemo', 'SilentAuthDemo')
tests_group = main_group.new_group('SilentAuthDemoTests', 'SilentAuthDemoTests')

# App subgroups
app_subgroup      = app_group.new_group('App', 'App')
resources_group   = app_group.new_group('Resources', 'Resources')
networking_group  = app_group.new_group('Networking', 'Networking')
models_group      = app_group.new_group('Models', 'Models')
theme_group       = app_group.new_group('Theme', 'Theme')
features_group    = app_group.new_group('Features', 'Features')
login_group       = features_group.new_group('Login', 'Login')
verified_group    = features_group.new_group('Verified', 'Verified')
devmode_group     = features_group.new_group('DevMode', 'DevMode')

# Add App source files — path is just the filename; the group hierarchy provides the directory
['SilentAuthDemoApp.swift', 'ContentView.swift'].each do |f|
  ref = app_subgroup.new_file(f)
  app_target.add_file_references([ref])
end

# Add Networking source files
['APIClient.swift', 'CellularAuthClient.swift', 'APIError.swift', 'CellularAuthError.swift',
 'Configuration.swift', 'CellularRequestClientProtocol.swift', 'VerificationService.swift',
 'VerificationServiceProtocol.swift'].each do |f|
  ref = networking_group.new_file(f)
  app_target.add_file_references([ref])
end

# Add Models source files
['LogEvent.swift', 'LogStage.swift', 'AnyCodable.swift', 'VerificationState.swift'].each do |f|
  ref = models_group.new_file(f)
  app_target.add_file_references([ref])
end

# Add Theme source files
['VonageBrand.swift'].each do |f|
  ref = theme_group.new_file(f)
  app_target.add_file_references([ref])
end

# Add Login feature files (path is relative to group, not absolute)
['LoginViewModel.swift', 'LoginView.swift'].each do |f|
  ref = login_group.new_file(f)
  app_target.add_file_references([ref])
end

# Add Verified feature files
['VerifiedView.swift'].each do |f|
  ref = verified_group.new_file(f)
  app_target.add_file_references([ref])
end

# Add DevMode feature files
['DevConsoleView.swift', 'LogEventRow.swift'].each do |f|
  ref = devmode_group.new_file(f)
  app_target.add_file_references([ref])
end

# Add test files
['SmokeTests.swift'].each do |f|
  ref = tests_group.new_file(f)
  test_target.add_file_references([ref])
end

# Add Networking test group and files
networking_tests = tests_group.new_group('Networking', 'Networking')
['APIClientTests.swift', 'CellularAuthClientTests.swift'].each do |f|
  ref = networking_tests.new_file(f)
  test_target.add_file_references([ref])
end

# Add Features/Login test group and files
features_tests = tests_group.new_group('Features', 'Features')
login_tests = features_tests.new_group('Login', 'Login')
['VerificationStateTests.swift', 'LoginViewModelTests.swift', 'LogRedactionTests.swift',
 'LogStageTests.swift'].each do |f|
  ref = login_tests.new_file(f)
  test_target.add_file_references([ref])
end

# ── SPM dependency: VonageClientLibrary ──────────────────────────────────────
# XCRemoteSwiftPackageReference — added to the project, product linked to app target
spm_url = 'https://github.com/Vonage/vonage-ios-client-library.git'

pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref.repositoryURL = spm_url
pkg_ref.requirement = { kind: 'upToNextMajorVersion', minimumVersion: '1.0.0' }
project.root_object.package_references << pkg_ref

# Link VonageClientLibrary product to app target
pkg_proxy_app = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
pkg_proxy_app.package = pkg_ref
pkg_proxy_app.product_name = 'VonageClientLibrary'
app_target.package_product_dependencies << pkg_proxy_app

build_file_app = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file_app.product_ref = pkg_proxy_app
app_target.frameworks_build_phase.files << build_file_app

# Link VonageClientLibrary product to test target as well
pkg_proxy_test = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
pkg_proxy_test.package = pkg_ref
pkg_proxy_test.product_name = 'VonageClientLibrary'
test_target.package_product_dependencies << pkg_proxy_test

build_file_test = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file_test.product_ref = pkg_proxy_test
test_target.frameworks_build_phase.files << build_file_test

# ── Save ─────────────────────────────────────────────────────────────────────
project.save
puts "Created #{PROJ_PATH}"
