import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23PortableReviewCodingTests: XCTestCase {
    func testReleasedReviewScalarsRoundTripInTheirExactWireForms() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let request = try ReviewRequestPublicIDV1("review-request-23")
        let requestBytes = try encoder.encode(request)
        XCTAssertEqual(requestBytes, Data("\"review-request-23\"".utf8))
        XCTAssertEqual(try decoder.decode(ReviewRequestPublicIDV1.self, from: requestBytes), request)
        let proof = try ReviewCapabilityProofV1(rawBytes: Data(repeating: 0x23, count: 32))
        let proofBytes = try encoder.encode(proof)
        XCTAssertEqual(proofBytes, try encoder.encode(proof.rawBytes))
        XCTAssertEqual(try decoder.decode(ReviewCapabilityProofV1.self, from: proofBytes), proof)
        for malformed in ["{\"rawValue\":\"review-request-23\"}", "23", "\"\"", "\"非ASCII\""] {
            XCTAssertThrowsError(try decoder.decode(ReviewRequestPublicIDV1.self, from: Data(malformed.utf8)))
        }
        for malformed in ["{\"rawBytes\":\"Iw==\"}", "23", "\"Iw==\""] {
            XCTAssertThrowsError(try decoder.decode(ReviewCapabilityProofV1.self, from: Data(malformed.utf8)))
        }
    }

    func testCanonicalResponseRetainsTypedIdentityAndProofAcrossWireAndWrapperReadback() throws {
        let vector = try ReviewCapabilityProofVectorV1.rv1001()
        let response = try ReviewResponseEnvelopeV1(
            responsePublicID: "review-response-23", requestPublicID: vector.input.requestPublicID,
            body: try ReviewResponseBodyV1(disposition: .acknowledged,
                author: try ResponseAuthorAssertionV1(displayName: "External reviewer")),
            proof: vector.proof, canonicalBodyDigest: vector.input.canonicalResponseBodyDigest)
        let bytes = try JSONEncoder().encode(response)
        XCTAssertEqual(try JSONDecoder().decode(ReviewResponseEnvelopeV1.self, from: bytes), response)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["requestPublicID"] as? String, vector.input.requestPublicID.rawValue)
        XCTAssertEqual(object["proof"] as? String, vector.proof.rawBytes.base64EncodedString())
        let wrapper = try CanonicalReviewResponseBytesV1(response: response)
        XCTAssertNoThrow(try wrapper.validate())
        let reopened = try JSONDecoder().decode(CanonicalReviewResponseBytesV1.self,
            from: JSONEncoder().encode(wrapper))
        XCTAssertEqual(reopened, wrapper)
        XCTAssertEqual(reopened.canonicalBytes, wrapper.canonicalBytes)
        XCTAssertNoThrow(try reopened.validate())
    }
}
