# Arc-shaped WeChat —— 构建 TrollFools 用的裸 dylib
#
# 用法（macOS + Xcode 命令行工具）:
#     make            # 产出 build/ArcShapedWeChat.dylib
#     make clean
#
# 刻意不使用 theos / Logos / MobileSubstrate：
#   TrollFools 对"加密的 App Store 应用"（微信正是）只支持 bare dynamic library，
#   任何额外的 dylib 依赖都会让 dyld 加载失败。这里只链接系统框架。

TARGET  := ArcShapedWeChat
SDK     := iphoneos
ARCHS   := arm64
MIN_VER := 14.0
BUILD   := build

SOURCES := ArcShapedWeChat.m \
           ArcHook.m \
           ArcPrefs.m \
           ArcStatus.m \
           ArcClassConfig.m \
           ArcCardEngine.m \
           ArcForceRound.m \
           ArcSettingsController.m \
           ArcClassSettings.m

HEADERS := $(wildcard *.h)

SDKROOT := $(shell xcrun --sdk $(SDK) --show-sdk-path)
CC      := xcrun -sdk $(SDK) clang

CFLAGS  := $(foreach a,$(ARCHS),-arch $(a)) \
           -isysroot $(SDKROOT) \
           -miphoneos-version-min=$(MIN_VER) \
           -fobjc-arc \
           -O2 -Wall \
           -Wno-deprecated-declarations \
           -Wno-unused-variable

LDFLAGS := -dynamiclib \
           -install_name @rpath/$(TARGET).dylib \
           -Xlinker -dead_strip

FRAMEWORKS := -framework Foundation \
              -framework UIKit \
              -framework QuartzCore \
              -framework CoreGraphics

.PHONY: all clean verify

all: $(BUILD)/$(TARGET).dylib

$(BUILD)/$(TARGET).dylib: $(SOURCES) $(HEADERS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) $(FRAMEWORKS) $(SOURCES) -o $@
	@echo ""
	@echo "  ✔ $@"
	@echo ""
	@$(MAKE) --no-print-directory verify

verify:
	@echo "  install_name:"; otool -D $(BUILD)/$(TARGET).dylib 2>/dev/null | tail -n +2
	@echo "  linked libraries:"; otool -L $(BUILD)/$(TARGET).dylib 2>/dev/null | tail -n +2
	@echo ""
	@if otool -L $(BUILD)/$(TARGET).dylib | grep -qi substrate; then \
		echo "  ✘ 检测到 substrate 依赖，TrollFools 场景会加载失败"; exit 1; \
	else \
		echo "  ✔ 无第三方依赖，可直接交给 TrollFools 注入"; \
	fi

clean:
	rm -rf $(BUILD)
