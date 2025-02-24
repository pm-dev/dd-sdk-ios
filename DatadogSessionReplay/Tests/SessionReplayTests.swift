/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogSessionReplay

class SessionReplayTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: SessionReplay.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = FeatureRegistrationCoreMock()
        config = SessionReplay.Configuration(replaySampleRate: 100)
    }

    override func tearDown() {
        core = nil
        config = nil
        XCTAssertEqual(FeatureRegistrationCoreMock.referenceCount, 0)
    }

    func testWhenEnabled_itRegistersSessionReplayFeature() {
        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(core.get(feature: SessionReplayFeature.self))
        XCTAssertNotNil(core.get(feature: ResourcesFeature.self))
    }

    func testWhenEnabledInNOPCore_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // When
        SessionReplay.enable(with: config, in: NOPDatadogCore())

        // Then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized before calling `SessionReplay.enable(with:)`."
        )
    }

    // MARK: - Configuration Tests

    func testWhenEnabledWithDefaultConfiguration() throws {
        config = SessionReplay.Configuration(replaySampleRate: 42)

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, 42)
        XCTAssertEqual(sr.recordingCoordinator.privacy, .mask)
        XCTAssertNil((sr.requestBuilder as? SegmentRequestBuilder)?.customUploadURL)
        let r = try XCTUnwrap(core.get(feature: ResourcesFeature.self))
        XCTAssertNil((r.requestBuilder as? ResourceRequestBuilder)?.customUploadURL)
    }

    func testWhenEnabledWithReplaySampleRate() throws {
        let random: Float = .mockRandom(min: 0, max: 100)
        config.replaySampleRate = random

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, random)
    }

    func testWhenEnabledWithDefaultPrivacyLevel() throws {
        let random: PrivacyLevel = .mockRandom()
        config.defaultPrivacyLevel = random

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.privacy, random)
    }

    func testWhenEnabledWithCustomEndpoint() throws {
        let random: URL = .mockRandom()
        config.customEndpoint = random

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual((sr.requestBuilder as? SegmentRequestBuilder)?.customUploadURL, random)
    }

    func testWhenEnabledWithDebugSDKArgument() throws {
        // Given
        config.replaySampleRate = .mockRandom(min: 0, max: 100)
        config.debugSDK = true

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, 100)
    }

    func testWhenEnabledWithNoDebugSDKArgument() throws {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        config.replaySampleRate = random
        config.debugSDK = false

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, random)
    }

    func testItDoesntStartFeatureWhenSamplingRateIsZero() throws {
        // Given
        config.replaySampleRate = 0

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        XCTAssertNil(core.get(feature: SessionReplayFeature.self))
        XCTAssertNil(core.get(feature: ResourcesFeature.self))
    }
}
