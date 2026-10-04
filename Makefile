APP := WASD.app
BIN := $(APP)/Contents/MacOS/WASD
# 不写 -target 时，当前工具链会把最低系统标成 28.0，在 macOS 27 上无法打开。
TARGET := $(shell uname -m)-apple-macosx13.0

# 自签名代码签名证书（make cert 生成）。固定身份让 TCC 权限跨构建、跨重启保持稳定；
# 证书不存在时回退 ad-hoc 签名（--sign -），但每次重编译都可能要重新授权。
CERT := WASD Signing
SIGN := $(shell security find-identity -p codesigning 2>/dev/null | grep -q "$(CERT)" && echo "$(CERT)" || echo "-")

build:
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swiftc -O -target $(TARGET) -import-objc-header Sources/WASD-Bridging-Header.h -o $(BIN) Sources/main.swift Sources/capslock.c -framework IOKit -framework Carbon
	cp Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --sign "$(SIGN)" --force --deep $(APP)
	@echo "构建完成: $(APP)（签名: $(SIGN)）"

# 生成自签名代码签名证书并导入登录钥匙串（一次性，导入时可能弹钥匙串授权框）
# 需要 basicConstraints CA:TRUE，否则自签根无法通过链式校验，codesign 认不出该身份
cert:
	@if security find-identity -p codesigning 2>/dev/null | grep -q "$(CERT)"; then \
		echo "证书已存在: $(CERT)"; \
	else \
		security delete-identity -c "$(CERT)" >/dev/null 2>&1; \
		tmpdir=$$(mktemp -d); \
		openssl req -x509 -newkey rsa:2048 -keyout $$tmpdir/key.pem -out $$tmpdir/cert.pem \
			-days 3650 -nodes -subj "/CN=$(CERT)" \
			-addext "basicConstraints=critical,CA:TRUE" \
			-addext "keyUsage=critical,digitalSignature,keyCertSign" \
			-addext "extendedKeyUsage=codeSigning" && \
		openssl pkcs12 -export -out $$tmpdir/cert.p12 -inkey $$tmpdir/key.pem \
			-in $$tmpdir/cert.pem -passout pass:cert-tmp && \
		security import $$tmpdir/cert.p12 -P "cert-tmp" -A && \
		echo "证书已生成并导入登录钥匙串: $(CERT)" && \
		echo "如构建时报 errSecInternalComponent，请执行一次: security set-key-partition-list -S apple-tool:,apple: -s"; \
		rm -rf $$tmpdir; \
	fi

icon:
	swift Scripts/make_icon.swift

run: build
	open $(APP)

test: build
	swiftc -O -target $(TARGET) -o Tests/remap_test Tests/remap_test.swift
	codesign --sign "$(SIGN)" --force --identifier local.wasd.remap-test Tests/remap_test
	pkill -x WASD || true
	pkill -x CapsJ4Mac || true
	sleep 1
	WASD_TAP_STATE=1 nohup ./$(BIN) > /tmp/wasd-test.log 2>&1 & sleep 2
	./Tests/remap_test; status=$$?; \
	pkill -x WASD || true; sleep 1; \
	open $(APP); \
	exit $$status

clean:
	rm -rf $(APP) CapsJ4Mac.app

.PHONY: build cert icon run test clean
