.PHONY: deps build test app dist install run icon clean

# With only the Command Line Tools (no Xcode), Swift Testing lives outside the default search paths.
DEV := $(shell xcode-select -p)
ifneq (,$(findstring CommandLineTools,$(DEV)))
TEST_FLAGS := -Xswiftc -F -Xswiftc $(DEV)/Library/Developer/Frameworks \
	-Xlinker -F -Xlinker $(DEV)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(DEV)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(DEV)/Library/Developer/usr/lib
endif

deps:
	scripts/fetch-deps.sh

build: deps
	swift build

test: deps
	swift test $(TEST_FLAGS)

app:
	scripts/build-app.sh

dist:
	scripts/build-app.sh --dist

install: app
	rm -rf /Applications/Hark.app
	cp -R build/Hark.app /Applications/
	open /Applications/Hark.app

run: app
	open build/Hark.app

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build build
