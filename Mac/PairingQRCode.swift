import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum PairingQRCode {
    static func makeCGImage(_ value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let symbol = filter.outputImage else { return nil }
        // Four white modules around the symbol are required for reliable scanning.
        let extent = CGRect(x: 0, y: 0, width: symbol.extent.width + 8, height: symbol.extent.height + 8)
        let background = CIImage(color: .white).cropped(to: extent)
        let padded = symbol.transformed(by: CGAffineTransform(translationX: 4, y: 4)).composited(over: background)
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    static func image(_ value: String) -> NSImage? {
        guard let image = makeCGImage(value) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
