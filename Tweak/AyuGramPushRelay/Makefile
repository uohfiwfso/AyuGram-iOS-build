NAME = AyuGramPushRelay
TARGET = $(NAME).dylib
BUILD_DIR = build
INSTALL_DIR = /var/jb/Library/MobileSubstrate/DynamicLibraries

# Rootless-раскладка: префикс /var/jb. Внутри .deb файлы лежат по путям
# ./var/jb/... — так же устроены настоящие rootless-пакеты (проверено на
# deb'ах из bootstrap Dopamine: basebin-link.deb, libroot.deb).
ROOTLESS_PREFIX = /var/jb

VERSION = 1.0.0
DEB_NAME = $(NAME)_$(VERSION)_iphoneos-arm64.deb
DEB_DIR = $(BUILD_DIR)/deb
STAGE_DIR = $(DEB_DIR)/$(NAME)_$(VERSION)_iphoneos-arm64

SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS = 15.0
ARCHS = arm64 arm64e

CFLAGS = -fobjc-arc -Wall -Wno-unused-variable -Wno-objc-method-access \
         -isysroot $(SDK) -miphoneos-version-min=$(MIN_IOS) \
         $(foreach arch,$(ARCHS),-arch $(arch))

LDFLAGS = -dynamiclib -framework Foundation -framework UIKit -framework UserNotifications \
          -Wl,-install_name,@rpath/$(TARGET)

.PHONY: all clean install deb

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

# Сборка .deb для установки через Sileo/Zebra или dpkg -i.
#
# Собирает packaging/build_deb.py, а не dpkg-deb: на macOS-раннерах GitHub
# dpkg-deb нет, а ставить dpkg ради одной упаковки смысла нет. Сборщик делает
# ровно то же, что dpkg-deb -b (ar-архив: debian-binary + control.tar.gz +
# data.tar.gz), и проверен A/B-тестом с настоящим dpkg-deb: структура
# data.tar и результат установки совпадают.
deb: all
	@rm -rf $(DEB_DIR)
	@mkdir -p $(STAGE_DIR)/DEBIAN
	@mkdir -p $(STAGE_DIR)$(ROOTLESS_PREFIX)/Library/MobileSubstrate/DynamicLibraries
	@install -m 644 $(BUILD_DIR)/$(TARGET) $(STAGE_DIR)$(ROOTLESS_PREFIX)/Library/MobileSubstrate/DynamicLibraries/$(TARGET)
	@install -m 644 $(NAME).plist $(STAGE_DIR)$(ROOTLESS_PREFIX)/Library/MobileSubstrate/DynamicLibraries/$(NAME).plist
	@install -m 644 packaging/control $(STAGE_DIR)/DEBIAN/control
	@install -m 644 packaging/triggers $(STAGE_DIR)/DEBIAN/triggers
	@install -m 755 packaging/postinst $(STAGE_DIR)/DEBIAN/postinst
	@install -m 755 packaging/postrm $(STAGE_DIR)/DEBIAN/postrm
	@mkdir -p $(STAGE_DIR)$(ROOTLESS_PREFIX)/usr/share/doc/$(NAME)
	@install -m 644 README.md $(STAGE_DIR)$(ROOTLESS_PREFIX)/usr/share/doc/$(NAME)/README.md
	@python3 packaging/build_deb.py $(STAGE_DIR) $(DEB_DIR)/$(DEB_NAME) $(VERSION) iphoneos-arm64
	@echo "built $(DEB_DIR)/$(DEB_NAME)"

