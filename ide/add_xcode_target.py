#!/usr/bin/env python3
"""Add GhosttyIDE target to the Xcode project."""

import re
import sys

PBXPROJ = "macos/Ghostty.xcodeproj/project.pbxproj"

def insert_before(content, marker, text):
    idx = content.find(marker)
    if idx == -1:
        print(f"ERROR: marker not found: {marker}", file=sys.stderr)
        sys.exit(1)
    return content[:idx] + text + content[idx:]

def insert_after(content, marker, text):
    idx = content.find(marker)
    if idx == -1:
        print(f"ERROR: marker not found: {marker}", file=sys.stderr)
        sys.exit(1)
    end = idx + len(marker)
    return content[:end] + text + content[end:]

with open(PBXPROJ) as f:
    content = f.read()

# ── 1. PBXBuildFile section ──
content = insert_before(content, "/* End PBXBuildFile section */", """\
\t\tC1DE0000000000000000000B /* GhosttyKit.xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = A5D495A1299BEC7E00DD1313 /* GhosttyKit.xcframework */; };
\t\tC1DE0000000000000000000C /* Carbon.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = A56B880A2A840447007A0E29 /* Carbon.framework */; };
\t\tC1DE0000000000000000000D /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = C1DE0000000000000000000F /* Sparkle */; };
\t\tC1DE0000000000000000000E /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = A5B30538299BEAAB0047F10C /* Assets.xcassets */; };
\t\tC1DE00000000000000000010 /* bash-completion in Resources */ = {isa = PBXBuildFile; fileRef = FC9ABA9B2D0F538D0020D4C8 /* bash-completion */; };
\t\tC1DE00000000000000000011 /* bat in Resources */ = {isa = PBXBuildFile; fileRef = 29C15B1C2CDC3B2000520DD4 /* bat */; };
\t\tC1DE00000000000000000012 /* fish in Resources */ = {isa = PBXBuildFile; fileRef = A586167B2B7703CC009BDB1D /* fish */; };
\t\tC1DE00000000000000000013 /* ghostty in Resources */ = {isa = PBXBuildFile; fileRef = 55154BDF2B33911F001622DC /* ghostty */; };
\t\tC1DE00000000000000000014 /* locale in Resources */ = {isa = PBXBuildFile; fileRef = A546F1132D7B68D7003B11A0 /* locale */; };
\t\tC1DE00000000000000000015 /* man in Resources */ = {isa = PBXBuildFile; fileRef = A5985CE52C33060F00C57AD3 /* man */; };
\t\tC1DE00000000000000000016 /* nvim in Resources */ = {isa = PBXBuildFile; fileRef = 9351BE8E2D22937F003B3499 /* nvim */; };
\t\tC1DE00000000000000000017 /* terminfo in Resources */ = {isa = PBXBuildFile; fileRef = A5A1F8842A489D6800D1E8BC /* terminfo */; };
\t\tC1DE00000000000000000018 /* vim in Resources */ = {isa = PBXBuildFile; fileRef = 552964E52B34A9B400030505 /* vim */; };
\t\tC1DE00000000000000000019 /* zsh in Resources */ = {isa = PBXBuildFile; fileRef = FC5218F92D10FFC7004C93E0 /* zsh */; };
\t\tC1DE0000000000000000001A /* Ghostty.icon in Resources */ = {isa = PBXBuildFile; fileRef = A553F4122E06EB1600257779 /* Ghostty.icon */; };
\t\tC1DE0000000000000000001B /* Ghostty.sdef in Resources */ = {isa = PBXBuildFile; fileRef = 8F3A9B4B2FA6B88000A18D13 /* Ghostty.sdef */; };
""")

# ── 2. PBXFileReference section ──
content = insert_before(content, "/* End PBXFileReference section */",
    "\t\tC1DE00000000000000000005 /* GhosttyIDE.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = GhosttyIDE.app; sourceTree = BUILT_PRODUCTS_DIR; };\n")

# ── 3. PBXFileSystemSynchronizedBuildFileExceptionSet section ──
content = insert_before(content, "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */", """\
\t\tC1DE0000000000000000000A /* PBXFileSystemSynchronizedBuildFileExceptionSet */ = {
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\tApp/iOS/iOSApp.swift,
\t\t\t\t"Features/Custom App Icon/DockTilePlugin.swift",
\t\t\t\t"Ghostty/Surface View/SurfaceView_UIKit.swift",
\t\t\t);
\t\t\ttarget = C1DE00000000000000000001 /* GhosttyIDE */;
\t\t};
""")

# ── 4. Update Sources root group to include IDE exception set ──
content = content.replace(
    "8193245D2F24E80800A9ED8F /* PBXFileSystemSynchronizedBuildFileExceptionSet */, ); explicitFileTypes",
    "8193245D2F24E80800A9ED8F /* PBXFileSystemSynchronizedBuildFileExceptionSet */, C1DE0000000000000000000A /* PBXFileSystemSynchronizedBuildFileExceptionSet */, ); explicitFileTypes"
)

# ── 5. PBXFrameworksBuildPhase section ──
content = insert_before(content, "/* End PBXFrameworksBuildPhase section */", """\
\t\tC1DE00000000000000000003 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\tC1DE0000000000000000000D /* Sparkle in Frameworks */,
\t\t\t\tC1DE0000000000000000000C /* Carbon.framework in Frameworks */,
\t\t\t\tC1DE0000000000000000000B /* GhosttyKit.xcframework in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
""")

# ── 6. Products group ──
content = content.replace(
    "\t\t\t\t8193244D2F24E6C000A9ED8F /* DockTilePlugin.plugin */,\n\t\t\t);\n\t\t\tname = Products;",
    "\t\t\t\t8193244D2F24E6C000A9ED8F /* DockTilePlugin.plugin */,\n\t\t\t\tC1DE00000000000000000005 /* GhosttyIDE.app */,\n\t\t\t);\n\t\t\tname = Products;"
)

# ── 7. PBXNativeTarget section ──
content = insert_before(content, "/* End PBXNativeTarget section */", """\
\t\tC1DE00000000000000000001 /* GhosttyIDE */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = C1DE00000000000000000006 /* Build configuration list for PBXNativeTarget "GhosttyIDE" */;
\t\t\tbuildPhases = (
\t\t\t\tC1DE00000000000000000002 /* Sources */,
\t\t\t\tC1DE00000000000000000003 /* Frameworks */,
\t\t\t\tC1DE00000000000000000004 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t81F82BC72E82815D001EDFA7 /* Sources */,
\t\t\t);
\t\t\tname = GhosttyIDE;
\t\t\tpackageProductDependencies = (
\t\t\t\tC1DE0000000000000000000F /* Sparkle */,
\t\t\t);
\t\t\tproductName = GhosttyIDE;
\t\t\tproductReference = C1DE00000000000000000005 /* GhosttyIDE.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
""")

# ── 8. PBXProject section - targets list ──
content = content.replace(
    "\t\t\t\t810ACC9E2E9D3301004F8F92 /* GhosttyUITests */,",
    "\t\t\t\t810ACC9E2E9D3301004F8F92 /* GhosttyUITests */,\n\t\t\t\tC1DE00000000000000000001 /* GhosttyIDE */,"
)

# ── 8b. PBXProject section - TargetAttributes ──
content = content.replace(
    "\t\t\t\t\tA5B30530299BEAAA0047F10C = {",
    "\t\t\t\t\tC1DE00000000000000000001 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t};\n\t\t\t\t\tA5B30530299BEAAA0047F10C = {"
)

# ── 9. PBXResourcesBuildPhase section ──
content = insert_before(content, "/* End PBXResourcesBuildPhase section */", """\
\t\tC1DE00000000000000000004 /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\tC1DE00000000000000000010 /* bash-completion in Resources */,
\t\t\t\tC1DE0000000000000000001A /* Ghostty.icon in Resources */,
\t\t\t\tC1DE00000000000000000011 /* bat in Resources */,
\t\t\t\tC1DE00000000000000000012 /* fish in Resources */,
\t\t\t\tC1DE0000000000000000001B /* Ghostty.sdef in Resources */,
\t\t\t\tC1DE00000000000000000013 /* ghostty in Resources */,
\t\t\t\tC1DE00000000000000000014 /* locale in Resources */,
\t\t\t\tC1DE00000000000000000015 /* man in Resources */,
\t\t\t\tC1DE00000000000000000016 /* nvim in Resources */,
\t\t\t\tC1DE00000000000000000017 /* terminfo in Resources */,
\t\t\t\tC1DE00000000000000000018 /* vim in Resources */,
\t\t\t\tC1DE00000000000000000019 /* zsh in Resources */,
\t\t\t\tC1DE0000000000000000000E /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
""")

# ── 10. PBXSourcesBuildPhase section ──
content = insert_before(content, "/* End PBXSourcesBuildPhase section */", """\
\t\tC1DE00000000000000000002 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
""")

# ── 11. XCBuildConfiguration section ──
# Insert three configs for the IDE target (Debug, Release, ReleaseLocal)
# These are the same as Ghostty's but with different bundle ID and display name.
content = insert_before(content, "/* End XCBuildConfiguration section */", """\
\t\tC1DE00000000000000000007 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = Ghostty;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = GhosttyDebug.entitlements;
\t\t\t\t"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEAD_CODE_STRIPPING = YES;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tEXECUTABLE_NAME = ghosttyide;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = "Ghostty-Info.plist";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "GhosttyIDE[DEBUG]";
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";
\t\t\t\tINFOPLIST_KEY_NSAppleEventsUsageDescription = "A program running within GhosttyIDE would like to use AppleScript.";
\t\t\t\tINFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "A program running within GhosttyIDE would like to use Bluetooth.";
\t\t\t\tINFOPLIST_KEY_NSCalendarsUsageDescription = "A program running within GhosttyIDE would like to access your Calendar.";
\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "A program running within GhosttyIDE would like to use the camera.";
\t\t\t\tINFOPLIST_KEY_NSContactsUsageDescription = "A program running within GhosttyIDE would like to access your Contacts.";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tINFOPLIST_KEY_NSLocalNetworkUsageDescription = "A program running within GhosttyIDE would like to access the local network.";
\t\t\t\tINFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary = "A program running within GhosttyIDE would like to use your location temporarily.";
\t\t\t\tINFOPLIST_KEY_NSLocationUsageDescription = "A program running within GhosttyIDE would like to access your location information.";
\t\t\t\tINFOPLIST_KEY_NSMainNibFile = MainMenu;
\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = "A program running within GhosttyIDE would like to use your microphone.";
\t\t\t\tINFOPLIST_KEY_NSMotionUsageDescription = "A program running within GhosttyIDE would like to access motion data.";
\t\t\t\tINFOPLIST_KEY_NSPhotoLibraryUsageDescription = "A program running within GhosttyIDE would like to access your Photo Library.";
\t\t\t\tINFOPLIST_KEY_NSRemindersUsageDescription = "A program running within GhosttyIDE would like to access your reminders.";
\t\t\t\tINFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "A program running within GhosttyIDE would like to use speech recognition.";
\t\t\t\tINFOPLIST_KEY_NSSystemAdministrationUsageDescription = "A program running within GhosttyIDE requires elevated privileges.";
\t\t\t\tINFOPLIST_PREPROCESS = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tMARKETING_VERSION = 0.1;
\t\t\t\t"OTHER_LDFLAGS[arch=*]" = "-lstdc++";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.ghosttyide.app.debug;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "Sources/App/macOS/ghostty-bridging-header.h";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\tC1DE00000000000000000008 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = Ghostty;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Ghostty.entitlements;
\t\t\t\t"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEAD_CODE_STRIPPING = YES;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tEXECUTABLE_NAME = ghosttyide;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = fast;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = "Ghostty-Info.plist";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = GhosttyIDE;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";
\t\t\t\tINFOPLIST_KEY_NSAppleEventsUsageDescription = "A program running within GhosttyIDE would like to use AppleScript.";
\t\t\t\tINFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "A program running within GhosttyIDE would like to use Bluetooth.";
\t\t\t\tINFOPLIST_KEY_NSCalendarsUsageDescription = "A program running within GhosttyIDE would like to access your Calendar.";
\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "A program running within GhosttyIDE would like to use the camera.";
\t\t\t\tINFOPLIST_KEY_NSContactsUsageDescription = "A program running within GhosttyIDE would like to access your Contacts.";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tINFOPLIST_KEY_NSLocalNetworkUsageDescription = "A program running within GhosttyIDE would like to access the local network.";
\t\t\t\tINFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary = "A program running within GhosttyIDE would like to use your location temporarily.";
\t\t\t\tINFOPLIST_KEY_NSLocationUsageDescription = "A program running within GhosttyIDE would like to access your location information.";
\t\t\t\tINFOPLIST_KEY_NSMainNibFile = MainMenu;
\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = "A program running within GhosttyIDE would like to use your microphone.";
\t\t\t\tINFOPLIST_KEY_NSMotionUsageDescription = "A program running within GhosttyIDE would like to access motion data.";
\t\t\t\tINFOPLIST_KEY_NSPhotoLibraryUsageDescription = "A program running within GhosttyIDE would like to access your Photo Library.";
\t\t\t\tINFOPLIST_KEY_NSRemindersUsageDescription = "A program running within GhosttyIDE would like to access your reminders.";
\t\t\t\tINFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "A program running within GhosttyIDE would like to use speech recognition.";
\t\t\t\tINFOPLIST_KEY_NSSystemAdministrationUsageDescription = "A program running within GhosttyIDE requires elevated privileges.";
\t\t\t\tINFOPLIST_PREPROCESS = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tMARKETING_VERSION = 0.1;
\t\t\t\t"OTHER_LDFLAGS[arch=*]" = "-lstdc++";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.ghosttyide.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "Sources/App/macOS/ghostty-bridging-header.h";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\tC1DE00000000000000000009 /* ReleaseLocal */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = Ghostty;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = GhosttyReleaseLocal.entitlements;
\t\t\t\t"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEAD_CODE_STRIPPING = YES;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tEXECUTABLE_NAME = ghosttyide;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = fast;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = "Ghostty-Info.plist";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = GhosttyIDE;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";
\t\t\t\tINFOPLIST_KEY_NSAppleEventsUsageDescription = "A program running within GhosttyIDE would like to use AppleScript.";
\t\t\t\tINFOPLIST_KEY_NSAudioCaptureUsageDescription = "A program running within GhosttyIDE would like to access your system's audio.";
\t\t\t\tINFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "A program running within GhosttyIDE would like to use Bluetooth.";
\t\t\t\tINFOPLIST_KEY_NSCalendarsUsageDescription = "A program running within GhosttyIDE would like to access your Calendar.";
\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "A program running within GhosttyIDE would like to use the camera.";
\t\t\t\tINFOPLIST_KEY_NSContactsUsageDescription = "A program running within GhosttyIDE would like to access your Contacts.";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tINFOPLIST_KEY_NSLocalNetworkUsageDescription = "A program running within GhosttyIDE would like to access the local network.";
\t\t\t\tINFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary = "A program running within GhosttyIDE would like to use your location temporarily.";
\t\t\t\tINFOPLIST_KEY_NSLocationUsageDescription = "A program running within GhosttyIDE would like to access your location information.";
\t\t\t\tINFOPLIST_KEY_NSMainNibFile = MainMenu;
\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = "A program running within GhosttyIDE would like to use your microphone.";
\t\t\t\tINFOPLIST_KEY_NSMotionUsageDescription = "A program running within GhosttyIDE would like to access motion data.";
\t\t\t\tINFOPLIST_KEY_NSPhotoLibraryUsageDescription = "A program running within GhosttyIDE would like to access your Photo Library.";
\t\t\t\tINFOPLIST_KEY_NSRemindersUsageDescription = "A program running within GhosttyIDE would like to access your reminders.";
\t\t\t\tINFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "A program running within GhosttyIDE would like to use speech recognition.";
\t\t\t\tINFOPLIST_KEY_NSSystemAdministrationUsageDescription = "A program running within GhosttyIDE requires elevated privileges.";
\t\t\t\tINFOPLIST_PREPROCESS = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tMARKETING_VERSION = 0.1;
\t\t\t\t"OTHER_LDFLAGS[arch=*]" = "-lstdc++";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.ghosttyide.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "Sources/App/macOS/ghostty-bridging-header.h";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = ReleaseLocal;
\t\t};
""")

# ── 12. XCConfigurationList section ──
content = insert_before(content, "/* End XCConfigurationList section */", """\
\t\tC1DE00000000000000000006 /* Build configuration list for PBXNativeTarget "GhosttyIDE" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tC1DE00000000000000000007 /* Debug */,
\t\t\t\tC1DE00000000000000000008 /* Release */,
\t\t\t\tC1DE00000000000000000009 /* ReleaseLocal */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = ReleaseLocal;
\t\t};
""")

# ── 13. XCSwiftPackageProductDependency section ──
content = insert_before(content, "/* End XCSwiftPackageProductDependency section */", """\
\t\tC1DE0000000000000000000F /* Sparkle */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = A51BFC252B30F1B700E92F16 /* XCRemoteSwiftPackageReference "Sparkle" */;
\t\t\tproductName = Sparkle;
\t\t};
""")

with open(PBXPROJ, 'w') as f:
    f.write(content)

print("Successfully added GhosttyIDE target to Xcode project.")
