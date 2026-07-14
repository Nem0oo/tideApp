TARGET = iphone:clang:latest:16.6
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Tide
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = Tide
Tide_FILES = ContentView.swift TideApp.swift LocationManager.swift TideService.swift SettingsView.swift TideChartView.swift
Tide_FRAMEWORKS = UIKit CoreLocation
Tide_RESOURCE_DIRS = Resources
include $(THEOS_MAKE_PATH)/application.mk
