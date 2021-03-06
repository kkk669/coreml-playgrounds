import ARKit
import PlaygroundSupport
import UIKit
import Vision

// Parameters
// The model is from here: https://docs-assets.developer.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyInt8LUT.mlmodel
let config = MLModelConfiguration()
config.allowLowPrecisionAccumulationOnGPU = true
config.computeUnits = .all
let model = try compileModel(at: #fileLiteral(resourceName: "YOLOv3TinyInt8LUT.mlmodel"), configuration: config)
model.featureProvider = try MLDictionaryFeatureProvider(dictionary: [
    "iouThreshold": 0.5,
    "confidenceThreshold": 0.3,
])

// ViewControllers
final class ViewController: PreviewViewController {
    let bboxLayer = CALayer()

    lazy var request: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: model, completionHandler: self.processDetections)
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.arView.session.delegate = self

        self.view.layer.addSublayer(self.bboxLayer)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.bboxLayer.position = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
    }

    func detect(imageBuffer: CVImageBuffer, orientation: CGImagePropertyOrientation) {
        try! VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: orientation)
            .perform([self.request])
    }

    func processDetections(for request: VNRequest, error: Error?) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)

        // Remove all bboxes
        self.bboxLayer.sublayers = nil

        request.results?
            .lazy
            .compactMap { $0 as? VNRecognizedObjectObservation }
            .forEach {
                let imgSize = self.bboxLayer.bounds.size;
                let bbox = VNImageRectForNormalizedRect($0.boundingBox, Int(imgSize.width), Int(imgSize.height))
                let cls = $0.labels[0]

                // Render a bounding box
                let shapeLayer = CALayer()
                shapeLayer.borderColor = #colorLiteral(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
                shapeLayer.borderWidth = 2
                shapeLayer.bounds = bbox
                shapeLayer.position = CGPoint(x: bbox.midX, y: bbox.midY)

                // Render a description
                let textLayer = CATextLayer()
                textLayer.string = "\(cls.identifier): \(cls.confidence)"
                textLayer.font = UIFont.preferredFont(forTextStyle: .body)
                textLayer.bounds = CGRect(x: 0, y: 0, width: bbox.width - 10, height: bbox.height - 10)
                textLayer.position = CGPoint(x: bbox.midX, y: bbox.midY)
                textLayer.foregroundColor = #colorLiteral(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
                textLayer.contentsScale = 2.0 // Retina Display
                textLayer.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))

                shapeLayer.addSublayer(textLayer)
                self.bboxLayer.addSublayer(shapeLayer)
            }

        CATransaction.commit()
    }
}

extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let imageBuffer = frame.capturedImage

        let orientation = CGImagePropertyOrientation(interfaceOrientation: UIScreen.main.orientation)

        var size = CVImageBufferGetDisplaySize(imageBuffer)
        if orientation == .right || orientation == .left {
            size = CGSize(width: size.height, height: size.width)
        }
        let scale = self.view.bounds.size / size
        let maxScale = fmax(scale.width, scale.height)
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        self.bboxLayer.setAffineTransform(CGAffineTransform(scaleX: maxScale, y: -maxScale))
        self.bboxLayer.bounds = CGRect(origin: .zero, size: size)
        self.bboxLayer.position = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
        CATransaction.commit()

        self.detect(imageBuffer: imageBuffer, orientation: orientation)
    }
}

PlaygroundPage.current.wantsFullScreenLiveView = true
PlaygroundPage.current.liveView = ViewController()
