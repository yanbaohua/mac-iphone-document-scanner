import AVFoundation
import AppKit
import SwiftUI

struct PreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let quadrilateral: DocumentQuadrilateral?

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
        view.updateOverlay(quadrilateral)
    }
}

final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private let documentLayer = CAShapeLayer()
    private var quadrilateral: DocumentQuadrilateral?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        previewLayer.videoGravity = .resizeAspect
        documentLayer.fillColor = NSColor.clear.cgColor
        documentLayer.strokeColor = NSColor.systemGreen.cgColor
        documentLayer.lineWidth = 3
        documentLayer.lineJoin = .round
        layer?.addSublayer(previewLayer)
        layer?.addSublayer(documentLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        documentLayer.frame = bounds
        CATransaction.commit()
        drawOverlay()
    }

    func updateOverlay(_ quadrilateral: DocumentQuadrilateral?) {
        self.quadrilateral = quadrilateral
        drawOverlay()
    }

    private func drawOverlay() {
        guard let quadrilateral else {
            documentLayer.path = nil
            return
        }

        func layerPoint(_ point: CGPoint) -> CGPoint {
            previewLayer.layerPointConverted(
                fromCaptureDevicePoint: CGPoint(x: point.x, y: 1 - point.y)
            )
        }

        let path = CGMutablePath()
        path.move(to: layerPoint(quadrilateral.topLeft))
        path.addLine(to: layerPoint(quadrilateral.topRight))
        path.addLine(to: layerPoint(quadrilateral.bottomRight))
        path.addLine(to: layerPoint(quadrilateral.bottomLeft))
        path.closeSubpath()
        documentLayer.path = path
    }
}
