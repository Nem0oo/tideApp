TARGET = iphone:clang:latest:16.6
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Tide
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = Tide
Tide_FILES = ContentView.swift TideApp.swift LocationManager.swift TideService.swift SettingsView.swift TideChartView.swift SavedLocation.swift MapViewRepresentable.swift LocationPickerView.swift TideSnapshot.swift
Tide_FRAMEWORKS = UIKit CoreLocation MapKit WidgetKit
Tide_RESOURCE_DIRS = Resources
# App Group requis pour partager les données de marée avec le widget (voir TideWidgetExtension_CODESIGN_FLAGS
# ci-dessous) ; nécessite que le groupe group.fr.gcourtot.tide soit enregistré sur le compte Apple Developer.
Tide_CODESIGN_FLAGS = -STide.entitlements
include $(THEOS_MAKE_PATH)/application.mk

APPEX_NAME = TideWidgetExtension
TideWidgetExtension_FILES = TideWidgetBundle.swift TideSnapshot.swift
TideWidgetExtension_FRAMEWORKS = SwiftUI WidgetKit
TideWidgetExtension_RESOURCE_DIRS = WidgetResources
TideWidgetExtension_INSTALL_PATH = /Applications/Tide.app/PlugIns
# Theos force -e _NSExtensionMain pour les appex (mécanisme des extensions à principal class
# Objective-C) ; les widgets WidgetKit utilisent le point d'entrée `@main` généré par Swift,
# il faut donc reprendre la main sur le point d'entrée du linker.
TideWidgetExtension_LDFLAGS = -e _main
TideWidgetExtension_CODESIGN_FLAGS = -STideWidgetExtension.entitlements
include $(THEOS_MAKE_PATH)/appex.mk
