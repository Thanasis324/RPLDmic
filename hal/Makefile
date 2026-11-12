# RPLDmic.driver (Core Audio HAL plug-in) + rpldmic-probe. Build on macOS.
OUT        = build/RPLDmic.driver
ARCH       = -arch x86_64 -mmacosx-version-min=10.15
CXXFLAGS   = $(ARCH) -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter
FRAMEWORKS = -framework CoreAudio -framework CoreFoundation -framework IOKit

all: $(OUT) build/rpldmic-probe

$(OUT): RPLDmicDriver.cpp Info.plist ../kext/RPLDmic/RPLDmicShared.h
	@mkdir -p build
	rm -rf $(OUT) && mkdir -p $(OUT)/Contents/MacOS
	clang++ $(CXXFLAGS) -bundle -o $(OUT)/Contents/MacOS/RPLDmic RPLDmicDriver.cpp $(FRAMEWORKS)
	cp Info.plist $(OUT)/Contents/Info.plist
	codesign -f -s - $(OUT) || true
	@echo "built $(OUT)"; nm -gU $(OUT)/Contents/MacOS/RPLDmic | grep -E 'RPLDmic_Create|TGLDmic_Create'

build/rpldmic-probe: rpldmic-probe.c ../kext/RPLDmic/RPLDmicShared.h
	@mkdir -p build
	clang $(ARCH) -std=c11 -O2 -Wall -o $@ rpldmic-probe.c -framework IOKit -framework CoreFoundation
	codesign -f -s - $@ || true

clean:
	rm -rf build
