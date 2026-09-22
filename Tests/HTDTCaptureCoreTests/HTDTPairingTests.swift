import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #379: QR pairing payload validation, pinned-identity
/// normalization, and the paired-destination store's pair/forget/
/// revoke lifecycle.
final class HTDTPairingTests: XCTestCase {
    private let pin = "sha256:"
        + String(repeating: "ab", count: 32)

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func makePayload(
        endpointURL: String = "https://receiver.local:8443/ingest",
        pinnedIdentity: String? = nil,
        expiresAtUTC: String? = nil
    ) -> HTDTReceiverPairingPayload {
        HTDTReceiverPairingPayload(
            receiverInstanceID: "receiver-01",
            displayName: "Stage Mac",
            endpointURL: endpointURL,
            capabilityEndpointURL: "https://receiver.local:8443/caps",
            pinnedIdentity: pinnedIdentity ?? pin,
            pairingToken: "tok-123",
            projectRef: "proj-77",
            expiresAtUTC: expiresAtUTC
        )
    }

    private func payloadData(
        _ payload: HTDTReceiverPairingPayload
    ) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    func testPayloadDecodesAndVerificationCodeIsStable() throws {
        let decoded = try HTDTReceiverPairingPayload(
            data: payloadData(makePayload())
        )
        XCTAssertEqual(decoded.receiverInstanceID, "receiver-01")
        let code = decoded.verificationCode
        XCTAssertEqual(code.count, 9)
        XCTAssertTrue(code.contains("-"))
        // Same material -> same code; the code is a function of the
        // pin, not of time.
        let twin = try HTDTReceiverPairingPayload(
            data: payloadData(makePayload())
        )
        XCTAssertEqual(code, twin.verificationCode)
    }

    func testNonHTTPSEndpointRejected() throws {
        XCTAssertThrowsError(
            try HTDTReceiverPairingPayload(
                data: payloadData(
                    makePayload(endpointURL: "http://r.local/ingest")
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTPairingError,
                .nonSecureEndpoint
            )
        }
    }

    func testMalformedPinnedIdentityRejected() throws {
        for bad in ["sha256:xyz", "abcd", "sha256:"
            + String(repeating: "AB", count: 32)] {
            XCTAssertThrowsError(
                try HTDTReceiverPairingPayload(
                    data: payloadData(
                        makePayload(pinnedIdentity: bad)
                    )
                )
            ) { error in
                XCTAssertEqual(
                    error as? HTDTPairingError,
                    .invalidPinnedIdentity,
                    "expected pin \(bad) rejected"
                )
            }
        }
    }

    func testExpiredPayloadRejected() throws {
        XCTAssertThrowsError(
            try HTDTReceiverPairingPayload(
                data: payloadData(
                    makePayload(
                        expiresAtUTC: "2020-01-01T00:00:00Z"
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTPairingError,
                .pairingPayloadExpired
            )
        }
    }

    func testPinnedIdentityDigestTextNormalization() {
        // Only the exact `sha256:<64 lowercase hex>` form is a pin.
        XCTAssertEqual(
            HTDTPinnedIdentity.digestText(pin),
            String(repeating: "ab", count: 32)
        )
        XCTAssertNil(HTDTPinnedIdentity.digestText("not-a-pin"))
        XCTAssertNil(
            HTDTPinnedIdentity.digestText(
                "sha256:" + String(repeating: "AB", count: 32)
            )
        )
    }

    func testPairForgetAndRevoke() throws {
        let root = try makeRoot()
        let store = PairedHTDTDestinationStore(captureRoot: root)
        let payload = try HTDTReceiverPairingPayload(
            data: payloadData(makePayload())
        )

        let paired = try store.pair(payload: payload)
        XCTAssertEqual(paired.displayName, "Stage Mac")
        XCTAssertEqual(
            paired.pinnedIdentity,
            pin
        )
        XCTAssertEqual(
            paired.handoffDestination.kind,
            .endpoint
        )
        XCTAssertEqual(
            paired.handoffDestination.url,
            "https://receiver.local:8443/ingest"
        )

        // Re-pairing the same receiver instance replaces pin +
        // endpoint but keeps the destination id stable.
        let rePinned = try store.pair(
            payload: try HTDTReceiverPairingPayload(
                data: payloadData(
                    makePayload(
                        pinnedIdentity: "sha256:"
                            + String(repeating: "cd", count: 32)
                    )
                )
            )
        )
        XCTAssertEqual(
            rePinned.destinationID,
            paired.destinationID
        )
        XCTAssertEqual(
            rePinned.pinnedIdentity,
            "sha256:" + String(repeating: "cd", count: 32)
        )
        XCTAssertEqual(
            try store.activeDestinations().count,
            1
        )

        // Revoked destinations stay recorded but leave the active set.
        try store.revoke(destinationID: paired.destinationID)
        XCTAssertTrue(try store.activeDestinations().isEmpty)
        XCTAssertEqual(
            try store.load().destinations.count,
            1
        )

        // Forget deletes outright.
        try store.forget(destinationID: paired.destinationID)
        XCTAssertTrue(try store.load().destinations.isEmpty)
    }

    func testPairingPersistsAcrossStoreInstances() throws {
        let root = try makeRoot()
        let store = PairedHTDTDestinationStore(captureRoot: root)
        _ = try store.pair(
            payload: try HTDTReceiverPairingPayload(
                data: payloadData(makePayload())
            )
        )
        let reloaded = PairedHTDTDestinationStore(captureRoot: root)
        XCTAssertEqual(
            try reloaded.activeDestinations().count,
            1
        )
        XCTAssertEqual(
            try reloaded.destination(
                receiverInstanceID: "receiver-01"
            )?.pinnedIdentity,
            pin
        )
    }
}
