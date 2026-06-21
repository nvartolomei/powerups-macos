# disable warnings coming from pods, which are always noise from our perspective
inhibit_all_warnings!

def deployment_target_from_xcconfig()
    xcconfig_path = 'config/base.xcconfig'
    File.foreach(xcconfig_path) do |line|
        if line.start_with?('MACOSX_DEPLOYMENT_TARGET')
            target = line.split("=").last.strip
            puts "MACOSX_DEPLOYMENT_TARGET: #{target}"
            return target
        end
    end
    puts "\e[31mCouldn't read MACOSX_DEPLOYMENT_TARGET from #{xcconfig_path}\e[0m"
    exit 1
end

deployment_target = deployment_target_from_xcconfig()

platform :osx, deployment_target

target 'powerups-macos' do
  use_frameworks!
  pod 'ShortcutRecorder', :git => 'https://github.com/lwouis/ShortcutRecorder.git', :commit => '594b360e07a8a368ffec2567f77e465477b9994f'
  pod 'SwiftyBeaver', '1.9.0'
end

target 'unit-tests' do
  use_frameworks!
  pod 'ShortcutRecorder', :git => 'https://github.com/lwouis/ShortcutRecorder.git', :commit => '594b360e07a8a368ffec2567f77e465477b9994f'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # disable code signing which is unnecessary for pods
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      # set deployment_target for all pods, to avoid libarclite compiler error
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = deployment_target
    end
  end
end
