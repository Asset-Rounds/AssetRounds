import Foundation
import UserNotifications
import XCTest
@testable import FieldEvidenceApp

@MainActor final class V23DetailedReminderDeliveryTests: XCTestCase {
    private func instant(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func generic(_ fire: Date) -> NotificationSystemRequestV1 {
        .init(notification: .init(requestID: "C2200000-0000-0000-0000-000000000001".lowercased(),
            opaqueCorrelationToken: CompatibilityCanonicalV1.sha256(Data("private correlation".utf8))),
            fireAtUTC: fire)
    }

    func testGenericEncodingAndReadbackRetainExactLegacyShape() throws {
        struct LegacyRequest: Encodable {
            let notification: AppLockGenericNotificationV1
            let fireAtUTC: Date
        }
        let value = generic(try instant("2026-09-19T18:05:00Z"))
        let legacy = LegacyRequest(notification: value.notification, fireAtUTC: value.fireAtUTC)
        let bytes = try CompatibilityCanonicalV1.encode(legacy)
        XCTAssertEqual(try CompatibilityCanonicalV1.encode(value), bytes)
        XCTAssertEqual(try CompatibilityCanonicalV1.decode(NotificationSystemRequestV1.self, from: bytes), value)
        let system = try UserNotificationSystemAdapterV1.systemRequest(value)
        XCTAssertEqual(system.content.title, "AssetRounds reminder")
        XCTAssertEqual(system.content.body, "Open AssetRounds to view details.")
        for delivered in [false, true] {
            XCTAssertEqual(UserNotificationSystemAdapterV1.observation(system, delivered: delivered).request, value)
        }
    }

    func testBothKindsUseApprovedCopyAndTokenOnlySystemPayload() throws {
        let fire = try instant("2026-09-19T18:05:00Z")
        for kind in ScheduledWorkKindV1.allCases {
            let detail = try ReminderSystemDetailV1.make(kind: kind, fireAtUTC: fire,
                timeZoneIdentifier: "America/New_York")
            XCTAssertEqual(detail.title, kind == .roundSession ? "Round due" : "Work due")
            XCTAssertTrue(detail.body.hasPrefix("Due Sep 19, 2026 at 2:05 PM "))
            XCTAssertTrue(detail.body.hasSuffix("(UTC−04:00). Open AssetRounds to review."))
            XCTAssertNoThrow(try detail.validate())
            let value = NotificationSystemRequestV1(notification: generic(fire).notification,
                fireAtUTC: fire, detail: detail)
            let system = try UserNotificationSystemAdapterV1.systemRequest(value)
            XCTAssertEqual(system.content.userInfo.count, 1)
            XCTAssertEqual(system.content.userInfo["token"] as? String, value.notification.opaqueCorrelationToken)
            XCTAssertEqual(system.content.title, detail.title)
            XCTAssertEqual(system.content.body, detail.body)
            XCTAssertEqual(system.content.subtitle, "")
            XCTAssertEqual(try CompatibilityCanonicalV1.decode(NotificationSystemRequestV1.self,
                from: CompatibilityCanonicalV1.encode(value)), value)
            for delivered in [false, true] {
                XCTAssertEqual(UserNotificationSystemAdapterV1.observation(system, delivered: delivered).request, value)
            }
        }
    }

    func testFrozenZoneAndEffectiveInstantDistinguishDSTFold() throws {
        let first = try ReminderSystemDetailV1.make(kind: .roundSession,
            fireAtUTC: instant("2026-11-01T05:30:00Z"), timeZoneIdentifier: "America/New_York")
        let second = try ReminderSystemDetailV1.make(kind: .roundSession,
            fireAtUTC: instant("2026-11-01T06:30:00Z"), timeZoneIdentifier: "America/New_York")
        XCTAssertTrue(first.body.hasPrefix("Due Nov 1, 2026 at 1:30 AM "))
        XCTAssertTrue(first.body.hasSuffix("(UTC−04:00). Open AssetRounds to review."))
        XCTAssertTrue(second.body.hasPrefix("Due Nov 1, 2026 at 1:30 AM "))
        XCTAssertTrue(second.body.hasSuffix("(UTC−05:00). Open AssetRounds to review."))
        XCTAssertNotEqual(first, second)
        let utc = try ReminderSystemDetailV1.make(kind: .workPacket,
            fireAtUTC: instant("2026-09-19T18:05:00Z"), timeZoneIdentifier: "UTC")
        XCTAssertEqual(utc.body, "Due Sep 19, 2026 at 6:05 PM UTC (UTC+00:00). Open AssetRounds to review.")
        XCTAssertThrowsError(try ReminderSystemDetailV1.make(kind: .workPacket,
            fireAtUTC: instant("2026-09-19T18:05:00Z"), timeZoneIdentifier: "Not/AZone"))
    }

    func testDetailedReadbackRejectsUnapprovedCopyAndAncillaryFields() throws {
        let fire = try instant("2026-09-19T18:05:00Z")
        let detail = try ReminderSystemDetailV1.make(kind: .roundSession, fireAtUTC: fire,
            timeZoneIdentifier: "America/New_York")
        let value = NotificationSystemRequestV1(notification: generic(fire).notification,
            fireAtUTC: fire, detail: detail)
        let original = try UserNotificationSystemAdapterV1.systemRequest(value)
        let mutations: [(UNMutableNotificationContent) -> Void] = [
            { $0.title = "Round due: Asset 1" },
            { $0.body += " Customer information" },
            { $0.body = $0.body.replacingOccurrences(of: "2:05", with: "2:75") },
            { $0.subtitle = "Unexpected" },
            { $0.userInfo["assetID"] = "private" },
            { $0.sound = .default }
        ]
        for mutate in mutations {
            let content = try XCTUnwrap(original.content.mutableCopy() as? UNMutableNotificationContent)
            mutate(content)
            let changed = UNNotificationRequest(identifier: original.identifier,
                content: content, trigger: original.trigger)
            XCTAssertNil(UserNotificationSystemAdapterV1.observation(changed, delivered: false).request)
            XCTAssertNil(UserNotificationSystemAdapterV1.observation(changed, delivered: true).request)
        }
    }

    func testNumericZoneFallbackUsesExplicitOffsetWithoutDeviceDefaults() throws {
        let detail = try ReminderSystemDetailV1.make(kind: .workPacket,
            fireAtUTC: instant("2026-09-19T18:05:00Z"), timeZoneIdentifier: "Etc/GMT-3")
        XCTAssertEqual(detail.body, "Due Sep 19, 2026 at 9:05 PM (UTC+03:00). Open AssetRounds to review.")
        XCTAssertEqual(try ReminderSystemDetailV1.observed(title: detail.title, body: detail.body), detail)
    }

    func testFrozenOffsetCopyDoesNotResolveCurrentTimeZoneRules() throws {
        let fire = try instant("2026-11-01T06:30:00Z")
        let earlier = try ReminderSystemDetailV1.make(kind: .roundSession, fireAtUTC: fire,
            frozenUTCOffsetSeconds: -4 * 3600)
        let later = try ReminderSystemDetailV1.make(kind: .roundSession, fireAtUTC: fire,
            frozenUTCOffsetSeconds: -5 * 3600)
        XCTAssertEqual(earlier.body, "Due Nov 1, 2026 at 2:30 AM (UTC−04:00). Open AssetRounds to review.")
        XCTAssertEqual(later.body, "Due Nov 1, 2026 at 1:30 AM (UTC−05:00). Open AssetRounds to review.")
        XCTAssertNotEqual(earlier, later)
        let request = NotificationSystemRequestV1(notification: generic(fire).notification,
            fireAtUTC: fire, detail: earlier)
        let system = try UserNotificationSystemAdapterV1.systemRequest(request)
        XCTAssertEqual(UserNotificationSystemAdapterV1.observation(system, delivered: true).request, request)
        for invalid in [Int.min, Int.max, 64_801, 1] {
            XCTAssertThrowsError(try ReminderSystemDetailV1.make(kind: .workPacket, fireAtUTC: fire,
                frozenUTCOffsetSeconds: invalid))
        }
    }
}
