import Foundation
import CoreImage

@main
struct PairingTests {
    static func main() throws {
        let pairing = MirrorPairing(hosts: ["192.168.1.42", "169.254.12.34"], port: 48765, code: "01234567")!
        try check(MirrorPairing.decode(pairing.qrString) == pairing, "QR payload round trip preserves leading-zero code and multiple interfaces")
        try check(pairing.baseURLs.map(\.absoluteString) == ["http://192.168.1.42:48765", "http://169.254.12.34:48765"], "Connection URLs contain only validated hosts and port")
        let prefix = "psdmirror://pair?v=1&hosts=192.168.1.42&port=48765&code="
        let invalid = [
            "https://example.com/?code=01234567",
            "psdmirror://another-app?v=1&hosts=192.168.1.42&port=48765&code=01234567",
            pairing.qrString.replacingOccurrences(of: "v=1", with: "v=2"),
            pairing.qrString + "&code=99999999",
            pairing.qrString + "&extra=1",
            pairing.qrString + "#fragment",
            prefix + "1234567", prefix + "１２３４５６７８",
            prefix.replacingOccurrences(of: "48765", with: "0") + "01234567",
            prefix.replacingOccurrences(of: "48765", with: "65536") + "01234567",
            prefix.replacingOccurrences(of: "192.168.1.42", with: "192.168.1.256") + "01234567",
            prefix.replacingOccurrences(of: "192.168.1.42", with: "192.168.1.042") + "01234567",
            prefix.replacingOccurrences(of: "192.168.1.42", with: "127.0.0.1") + "01234567",
            prefix.replacingOccurrences(of: "192.168.1.42", with: "224.0.0.1") + "01234567",
            prefix.replacingOccurrences(of: "192.168.1.42", with: "example.com%2Fpath") + "01234567",
            String(repeating: "x", count: 2049)
        ]
        for text in invalid { try check(MirrorPairing.decode(text) == nil, "Reject invalid or unrelated QR payload") }
        try check(MirrorPairing(hosts: ["192.168.1.42", "192.168.1.42"], port: 48765, code: "01234567") == nil, "Duplicate interfaces rejected")
        try check(MirrorPairing(hosts: (1...9).map { "192.168.1.\($0)" }, port: 48765, code: "01234567") == nil, "Interface count bounded")

        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        for item in [pairing, MirrorPairing(hosts: (1...8).map { "192.168.100.\($0)" }, port: 65535, code: "99999999")!] {
            guard let image = PairingQRCode.makeCGImage(item.qrString) else { throw Failure.failed("QR rendering") }
            let decoded = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            try check(decoded.contains(item.qrString), "Rendered QR image decodes into the exact pairing payload")
        }
        print("All pairing and QR rendering checks passed.")
    }

    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.failed(message) }
        print("PASS \(message)")
    }
    enum Failure: Error { case failed(String) }
}
