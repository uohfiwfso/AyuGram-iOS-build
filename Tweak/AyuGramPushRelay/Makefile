NAME = AyuGramPushRelay
TARGET = $(NAME).dylib
BUILD_DIR = build
INSTALL_DIR = /var/jb/Library/MobileSubstrate/DynamicLibraries

SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS = 15.0
ARCHS = arm64 arm64e

CFLAGS = -fobjc-arc -Wall -Wno-unused-variable -Wno-objc-method-access \
         -isysroot $(SDK) -miphoneos-version-min=$(MIN_IOS) \
         $(foreach arch,$(ARCHS),-arch $(arch))

LDFLAGS = -dynamiclib -framework Foundation -framework UIKit -framework UserNotifications \
          -Wl,-install_name,@rpath/$(TARGET) \
          -Wl,-undefined,dynamic_lookup

.PHONY: all clean install

all:
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(BUILD_DIR)/$(TARGET) AyuGramPushRelay.m
	@echo "built $(BUILD_DIR)/$(TARGET)"

clean:
	rm -rf $(BUILD_DIR)

# Установка на устройство (rootless): положить dylib и plist в
# /var/jb/Library/MobileSubstrate/DynamicLibraries, затем респринг.
install: all
	cp $(BUILD_DIR)/$(TARGET) $(INSTALL_DIR)/
	cp $(NAME).plist $(INSTALL_DIR)/
	@echo "installed into $(INSTALL_DIR), now respring"
