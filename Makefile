PROJECT   := VishPrompt.xcodeproj
SCHEME    := VishPrompt
DERIVED   := build
APP       := $(DERIVED)/Build/Products/Debug/VishPrompt.app
XCB       := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.PHONY: gen regen build test test-class verify-test-can-fail verify-test-class-can-fail verify-ocr verify-sensor verify-tap-cpu record-taps verify-latency verify-stt verify-streaming verify-subscription verify-memory run release install clean logs

## Every recipe that filters xcodebuild through grep starts with `set -o pipefail`, so the
## pipeline reports xcodebuild's status rather than grep's. These targets used to end in
## `|| true`, which made them exit 0 even when the build or a test failed, so any VERIFY that
## relied on them proved nothing. Per recipe rather than .SHELLFLAGS: macOS ships GNU make
## 3.81, which ignores .SHELLFLAGS. `make verify-test-can-fail` is the proof.
SHELL := /bin/bash

## Generate VishPrompt.xcodeproj from project.yml (requires: brew install xcodegen).
## --use-cache leaves the project untouched when nothing has changed, which matters because
## rewriting it invalidates the optimised dependency builds and turns a short install into a
## ten-minute one. It still notices new source files, which a timestamp check on project.yml
## alone does not.
gen:
	@xcodegen generate --quiet --use-cache --cache-path .xcodegen-cache

## Force a regeneration even when the cache says nothing changed.
regen:
	xcodegen generate --quiet

## Build the Debug app
build: gen
	set -o pipefail; $(XCB) -configuration Debug build 2>&1 | grep -E 'error:|warning:|BUILD '

## Run the unit tests
test: gen
	set -o pipefail; $(XCB) test $(ONLY) 2>&1 | grep -E 'error:|Test Case .* (passed|failed)|Executed|BUILD |TEST '

## Run one test class, and fail unless it actually ran: zero tests executed (a renamed or
## missing class) and any skipped test both count as failures, not just a failing assertion.
## Usage: make test-class C=RedactorTests
test-class: gen
	@test -n "$(C)" || { echo "usage: make test-class C=<TestClass>"; exit 2; }
	scripts/test-class.sh "$(C)" $(XCB)

## Proves `make test` can fail: a canary test fails on request, and this target passes only
## if `make test` then exits non-zero.
verify-test-can-fail: gen
	! TEST_RUNNER_VISHPROMPT_CANARY=fail $(MAKE) --no-print-directory test ONLY=-only-testing:VishPromptTests/CanaryTests

## Proves `make test-class` can fail on a class that does not exist and on a skipped test.
verify-test-class-can-fail: gen
	! $(MAKE) --no-print-directory test-class C=NoSuchTestClass
	! TEST_RUNNER_VISHPROMPT_CANARY=skip $(MAKE) --no-print-directory test-class C=CanaryTests

## Run the speech tests against audio synthesised with `say`.
## First run downloads roughly 600 MB of Core ML models.
verify-stt: gen
	set -o pipefail; TEST_RUNNER_VISHPROMPT_STT=1 $(XCB) test -only-testing:VishPromptTests/SpeechIntegrationTests 2>&1 | \
		grep -E 'STT|error:|Test Case .* (passed|failed)|Executed|TEST '

## Run the subscription tests against the real `claude` command line tool.
## Spends real Claude subscription quota.
verify-subscription: gen
	set -o pipefail; TEST_RUNNER_VISHPROMPT_CLI=1 $(XCB) test -only-testing:VishPromptTests/SubscriptionIntegrationTests 2>&1 | \
		grep -E 'SUBSCRIPTION|error:|Test Case .* (passed|failed)|Executed|TEST '

## Run the streaming tests against audio from `say`. First run downloads the streaming model.
## Measure what the speech models cost in memory. VISHPROMPT_ENCODER=ane for the other placement.
verify-memory: gen
	set -o pipefail; TEST_RUNNER_VISHPROMPT_STT=1 TEST_RUNNER_VISHPROMPT_ENCODER=$(or $(VISHPROMPT_ENCODER),default) $(XCB) test -only-testing:VishPromptTests/MemoryIntegrationTests 2>&1 | \
		grep -E 'MEMORY|error:|Test Case .* (passed|failed)|Executed|TEST '

## Run real Vision OCR on the committed screenshots in Fixtures/ocr. Fails on a skip, like
## test-class, so it cannot pass without actually reading the images.
verify-ocr: gen
	TEST_RUNNER_VISHPROMPT_OCR=1 scripts/test-class.sh ScreenshotOCRTests $(XCB)

## Read the real palm-rest accelerometer for a few seconds. Needs an M2-or-later MacBook.
verify-sensor: gen
	TEST_RUNNER_VISHPROMPT_SENSOR=1 scripts/test-class.sh SPUAccelerometerLiveTests $(XCB)

## The chassis tap trigger's CPU cost on the real sensor, and that it stops on lock and low battery.
verify-tap-cpu: gen
	TEST_RUNNER_VISHPROMPT_TAP_CPU=1 scripts/test-class.sh ChassisTapCPUTests $(XCB)

## Guided recording of real palm-rest taps, typing, clicks and handling into Fixtures/taps/,
## for TapDetectorTests. Run it in a terminal and follow the prompts. ONLY=<scenario> redoes one.
record-taps:
	@mkdir -p build
	swiftc -O -o build/record-taps scripts/record-taps/main.swift VishPrompt/Core/Tap/SPUAccelerometer.swift VishPrompt/Core/Tap/TapInputGuard.swift VishPrompt/Core/Tap/TapDetector.swift VishPrompt/Core/Logging/Log.swift
	build/record-taps Fixtures/taps $(ONLY)

## Time the real key-up path on the Release build: 20 runs, median and p90, raw rows in
## build/latency/. Needs the speech models (downloaded on first run). See LatencyHarnessTests.
verify-latency: gen
	@mkdir -p build/latency
	TEST_RUNNER_VISHPROMPT_LATENCY=1 TEST_RUNNER_VISHPROMPT_LATENCY_CSV=$(CURDIR)/build/latency/latency-$$(date +%Y%m%d-%H%M%S).csv \
		scripts/test-class.sh LatencyHarnessTests $(XCB) -configuration Release ENABLE_TESTABILITY=YES ARCHS=arm64 ONLY_ACTIVE_ARCH=NO

verify-streaming: gen
	set -o pipefail; TEST_RUNNER_VISHPROMPT_STT=1 $(XCB) test -only-testing:VishPromptTests/StreamingIntegrationTests 2>&1 | \
		grep -E 'STREAMING|error:|Test Case .* (passed|failed)|Executed|TEST '

## Build the optimised Release app.
## ARCHS is passed here rather than in project.yml because Swift package targets are separate
## projects and do not inherit it. Apple Silicon only: FluidAudio's Float16 paths do not
## compile for x86_64, and Parakeet needs the Neural Engine regardless.
release: gen
	set -o pipefail; $(XCB) -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build 2>&1 | grep -E 'error:|BUILD '

## Build Release and install into ~/Applications.
## Do this once and launch from there: debug builds are ad-hoc signed, so macOS ties the
## Accessibility and Input Monitoring grants to the exact binary and a rebuild loses them.
install: release
	@mkdir -p "$(HOME)/Applications"
	@rm -rf "$(HOME)/Applications/VishPrompt.app"
	@cp -R "$(DERIVED)/Build/Products/Release/VishPrompt.app" "$(HOME)/Applications/"
	@echo "Installed to ~/Applications/VishPrompt.app"

## Build and launch the app (it lives in the menu bar)
run: build
	open "$(APP)"

## Stream the app's logs
logs:
	log stream --predicate 'subsystem == "com.vish.visprflow"' --level debug --style compact

clean:
	rm -rf $(DERIVED) $(PROJECT)
