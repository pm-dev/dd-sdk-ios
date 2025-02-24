/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogSessionReplay
@testable import TestUtilities

class SegmentRequestBuilderTests: XCTestCase {
    private let rumContext: RUMContext = .mockRandom() // all records must reference the same RUM context
    private var mockEvents: [Event] {
        let records = [
            EnrichedRecord(context: .mockWith(rumContext: self.rumContext), records: .mockRandom(count: 5)),
            EnrichedRecord(context: .mockWith(rumContext: self.rumContext), records: .mockRandom(count: 10)),
            EnrichedRecord(context: .mockWith(rumContext: self.rumContext), records: .mockRandom(count: 15)),
        ]
        return records.map { .mockWith(data: try! JSONEncoder().encode($0)) }
    }

    func testItCreatesPOSTRequest() throws {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        let request = try builder.request(for: mockEvents, with: .mockAny())

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testItSetsIntakeURL() {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: mockEvents, with: .mockWith(site: site))
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        XCTAssertEqual(try url(for: .us1), "https://browser-intake-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us3), "https://browser-intake-us3-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us5), "https://browser-intake-us5-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .eu1), "https://browser-intake-datadoghq.eu/api/v2/replay")
        XCTAssertEqual(try url(for: .ap1), "https://browser-intake-ap1-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us1_fed), "https://browser-intake-ddog-gov.com/api/v2/replay")
    }

    func testItSetsCustomIntakeURL() {
        // Given
        let randomURL: URL = .mockRandom()
        let builder = SegmentRequestBuilder(customUploadURL: randomURL, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: mockEvents, with: .mockWith(site: site))
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        let expectedURL = randomURL.absoluteStringWithoutQuery
        XCTAssertEqual(try url(for: .us1), expectedURL)
        XCTAssertEqual(try url(for: .us3), expectedURL)
        XCTAssertEqual(try url(for: .us5), expectedURL)
        XCTAssertEqual(try url(for: .eu1), expectedURL)
        XCTAssertEqual(try url(for: .ap1), expectedURL)
        XCTAssertEqual(try url(for: .us1_fed), expectedURL)
    }

    func testItSetsNoQueryParameters() throws {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())
        let context: DatadogContext = .mockRandom()

        // When
        let request = try builder.request(for: mockEvents, with: context)

        // Then
        XCTAssertEqual(request.url!.query, nil)
    }

    func testItSetsHTTPHeaders() throws {
        let randomApplicationName: String = .mockRandom(among: .alphanumerics)
        let randomVersion: String = .mockRandom(among: .decimalDigits)
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomClientToken: String = .mockRandom()
        let randomDeviceName: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()

        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())
        let context: DatadogContext = .mockWith(
            clientToken: randomClientToken,
            version: randomVersion,
            source: randomSource,
            sdkVersion: randomSDKVersion,
            applicationName: randomApplicationName,
            device: .mockWith(
                name: randomDeviceName,
                osName: randomDeviceOSName,
                osVersion: randomDeviceOSVersion
            )
        )

        // When
        let request = try builder.request(for: mockEvents, with: context)

        // Then
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.matches(regex: #"multipart\/form-data; boundary=([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})"#))
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomVersion) CFNetwork (\(randomDeviceName); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomSource)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertNil(request.allHTTPHeaderFields?["Content-Encoding"], "It must us no compression, because multipart file is compressed separately")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    func testItSetsHTTPBodyInExpectedFormat() throws {
        // Given
        let multipartSpy = MultipartBuilderSpy()
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock(), multipartBuilder: multipartSpy)

        // When
        let request = try builder.request(for: mockEvents, with: .mockWith(source: "ios"))

        // Then
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.matches(regex: "multipart/form-data; boundary=\(multipartSpy.boundary.uuidString)"))
        XCTAssertEqual(multipartSpy.formFiles.first?.filename, rumContext.sessionID)
        XCTAssertEqual(multipartSpy.formFiles.first?.mimeType, "application/octet-stream")
        XCTAssertEqual(multipartSpy.formFields["segment"], rumContext.sessionID)
        XCTAssertEqual(multipartSpy.formFields["application.id"], rumContext.applicationID)
        XCTAssertEqual(multipartSpy.formFields["view.id"], rumContext.viewID!)
        XCTAssertTrue(["true", "false"].contains(multipartSpy.formFields["has_full_snapshot"]!))
        XCTAssertEqual(multipartSpy.formFields["records_count"], "30")
        XCTAssertNotNil(multipartSpy.formFields["raw_segment_size"])
        XCTAssertNotNil(multipartSpy.formFields["start"])
        XCTAssertNotNil(multipartSpy.formFields["end"])
        XCTAssertEqual(multipartSpy.formFields["source"], "ios")
    }

    func testWhenBatchDataIsMalformed_itThrows() {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When, Then
        XCTAssertThrowsError(try builder.request(for: [.mockWith(data: "abc".utf8Data)], with: .mockAny()))
    }

    func testWhenSourceIsInvalid_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: telemetry)

        // When
        _ = try builder.request(for: mockEvents, with: .mockWith(source: "invalid source"))

        // Then
        XCTAssertEqual(
            telemetry.description,
            """
            Telemetry logs:
             - [error] [SR] Could not create segment source from provided string 'invalid source', kind: nil, stack: nil
            """
        )
    }
}
