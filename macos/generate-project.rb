require 'xcodeproj'

root = File.expand_path(__dir__)
project = Xcodeproj::Project.new(File.join(root, 'ChessWidget.xcodeproj'))
app = project.new_target(:application, 'ChessWidget', :osx, '14.0')
widget = project.new_target(:app_extension, 'ChessWidgetExtension', :osx, '14.0')
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = 'Vendor/ChessKit'
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package
product.product_name = 'ChessKit'
app.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
app.frameworks_build_phase.files << build_file
project.main_group.set_source_tree('SOURCE_ROOT')
shared = project.main_group.new_group('Shared', 'Shared')
app_group = project.main_group.new_group('ChessWidget', 'ChessWidget')
widget_group = project.main_group.new_group('ChessWidgetExtension', 'ChessWidgetExtension')
%w[ChessData.swift BoardView.swift LichessToken.swift].each do |file|
  ref = shared.new_file(file)
  app.source_build_phase.add_file_reference(ref)
  widget.source_build_phase.add_file_reference(ref)
end
pieces = shared.new_file('Pieces.xcassets')
app.resources_build_phase.add_file_reference(pieces)
widget.resources_build_phase.add_file_reference(pieces)
app.source_build_phase.add_file_reference(app_group.new_file('ChessWidgetApp.swift'))
app.source_build_phase.add_file_reference(app_group.new_file('BroadcastStream.swift'))
app.source_build_phase.add_file_reference(app_group.new_file('StockfishEngine.swift'))
app.source_build_phase.add_file_reference(app_group.new_file('ClockPanel.swift'))
app.source_build_phase.add_file_reference(app_group.new_file('FollowedPlayers.swift'))
app.resources_build_phase.add_file_reference(app_group.new_file('Assets.xcassets'))
widget.source_build_phase.add_file_reference(widget_group.new_file('ChessPositionWidget.swift'))
app.add_dependency(widget)
engine_phase = app.new_shell_script_build_phase('Embed Stockfish')
engine_phase.shell_script = '/bin/sh "${SRCROOT}/scripts/embed-stockfish.sh"'
engine_phase.show_env_vars_in_log = '0'
phase = app.new_copy_files_build_phase('Embed App Extensions')
phase.symbol_dst_subfolder_spec = :plug_ins
phase.add_file_reference(widget.product_reference, true)
[app, widget].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
    config.build_settings['MARKETING_VERSION'] = '1.0'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'ChessWidget.entitlements'
    config.build_settings['ENABLE_APP_SANDBOX'] = 'YES'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'cz.lichesswatch.ChessWidget'
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Chess Broadcast Widget'
  config.build_settings['INFOPLIST_FILE'] = 'ChessWidget/Info.plist'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
end
widget.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'cz.lichesswatch.ChessWidget.GameBoard'
  config.build_settings['INFOPLIST_FILE'] = 'ChessWidgetExtension/Info.plist'
  config.build_settings['SKIP_INSTALL'] = 'YES'
end
project.save
