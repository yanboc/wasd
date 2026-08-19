APP := CapsJ4Mac.app
BIN := $(APP)/Contents/MacOS/CapsJ4Mac

build:
	mkdir -p $(APP)/Contents/MacOS
	swiftc -O -import-objc-header Sources/CapsJ4Mac-Bridging-Header.h -o $(BIN) Sources/main.swift Sources/capslock.c -framework IOKit
	cp Info.plist $(APP)/Contents/Info.plist
	codesign --sign - --force --deep $(APP)
	@echo "构建完成: $(APP)"

run: build
	open $(APP)

test: build
	swiftc -O -o Tests/remap_test Tests/remap_test.swift
	-pkill -x CapsJ4Mac; sleep 1
	CAPSJ4MAC_TAP_STATE=1 nohup ./$(BIN) > /tmp/capsj4mac-test.log 2>&1 & sleep 2
	./Tests/remap_test
	-pkill -x CapsJ4Mac; sleep 1
	nohup ./$(BIN) > /tmp/capsj4mac.log 2>&1 & sleep 1
	@echo "测试完毕，已重启正式实例"

clean:
	rm -rf $(APP)

.PHONY: build run test clean
