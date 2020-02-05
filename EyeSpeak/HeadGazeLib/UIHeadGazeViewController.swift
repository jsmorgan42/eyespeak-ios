import Foundation
import ARKit

extension Notification.Name {
    static let applicationDidAcquireGaze = Notification.Name("applicationDidAcquireGaze")
    static let applicationDidLoseGaze = Notification.Name("applicationDidLoseGaze")
}

extension UIApplication {

    fileprivate class Storage {

        static var isGazeTrackingActive: Bool = false {
            didSet {
                guard oldValue != isGazeTrackingActive else { return }
                if isGazeTrackingActive {
                    NotificationCenter.default.post(name: .applicationDidAcquireGaze, object: nil)
                } else {
                    NotificationCenter.default.post(name: .applicationDidLoseGaze, object: nil)
                }
            }
        }
    }

    var isGazeTrackingActive: Bool {
        return Storage.isGazeTrackingActive
    }
}

class UIHeadGazeViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {
 
    private(set) var sceneview: ARSCNView?

    public var virtualCursorView: UIVirtualCursorView?

    private var previousGaze: UIHeadGaze? //inherent from UIHeadGazeCallback
    private var cursorPositionInterpolator = LowPassInterpolator<CGPoint>(filterFactor: 0.2, initialValue: .zero)
    private var ndcSmoothingInterpolator = LowPassInterpolator<SIMD2<Float>>(filterFactor: 0.05, initialValue: .zero)
    private var computedScale: CGFloat = 6

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneview = ARSCNView(frame: .zero)
        self.view.addSubview(sceneview!)
        sceneview?.translatesAutoresizingMaskIntoConstraints = false
        sceneview?.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        sceneview?.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
        sceneview?.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        sceneview?.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        virtualCursorView = UIVirtualCursorView(frame: self.view.bounds)
        self.view.addSubview(virtualCursorView!)
        virtualCursorView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        sceneview?.delegate = self
        sceneview?.session.delegate = self
        sceneview?.isHidden = true

        setupSceneNode()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetTracking()

        if let virtualCursorView = virtualCursorView {
            view.sendSubviewToBack(virtualCursorView)
        }

        if let sceneView = sceneview {
            sceneView.isHidden = false
            view.sendSubviewToBack(sceneView)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneview?.session.pause()
    }
    
    private func resetTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            return
        }

        let configuration = ARFaceTrackingConfiguration()
        configuration.worldAlignment = .camera
        sceneview?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    /**
     AR tracking loop, the virtual cursor position is update here
    */
    private var lastGazeNDCLocation = CGPoint(x: 0.5, y: 0.5)
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let faceAnchor = faceAnchor else { return }

        let lBlinkAmount = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        let rBlinkAmount = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0

        let leftBlink = lBlinkAmount > 0.05
        let rightBlink = rBlinkAmount > 0.05
        let isBlinking = leftBlink || rightBlink

        let cursorPosNDC: CGPoint

        if !isBlinking && faceAnchor.isTracked {
            let pos = updateGazeNDCLocationByARFaceAnchor(frame: frame, isBlinking: isBlinking)
            cursorPosNDC = cursorPositionInterpolator.update(with: pos, factor: nil)
            lastGazeNDCLocation = pos
        } else {
            cursorPosNDC = cursorPositionInterpolator.update(with: lastGazeNDCLocation)
        }

        guard let window = self.view.window else { return }

        // Generate head gaze event and invoke event callback methods
        var allGazes = Set<UIHeadGaze>()
        let curGaze: UIHeadGaze
        if let lastGaze = previousGaze {
            curGaze = UIHeadGaze(curPosition: cursorPosNDC, prevPosition: lastGaze.location(in: window), view: self.view, win: window, isLeftEyeBlinking: leftBlink, isRightEyeBlinking: rightBlink)
        } else {
            curGaze = UIHeadGaze(position: cursorPosNDC, view: self.view, win: window, isLeftEyeBlinking: leftBlink, isRightEyeBlinking: rightBlink)
        }

        allGazes.insert(curGaze)
        previousGaze = curGaze

        if faceAnchor.isTracked {
            let event = UIHeadGazeEvent(allGazes: allGazes)
            window.sendEvent(event)
        }
    }

    private var headNode: SCNNode?
    private var faceAnchor: ARFaceAnchor? {
        didSet {
            let oldTracked = oldValue?.isTracked ?? false
            let newTracked = faceAnchor?.isTracked ?? false
            if oldTracked && !newTracked {
                DispatchQueue.main.async {
                    UIApplication.Storage.isGazeTrackingActive = false
                }
            } else if !oldTracked && newTracked {
                DispatchQueue.main.async {
                    UIApplication.Storage.isGazeTrackingActive = true
                }
            }
        }
    }

    private let axesNode = loadModelFromAsset(named: "axes")

    private func setupSceneNode() {
        headNode?.addChildNode(axesNode)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR session failed")
    }

    /// - Tag: ARNodeTracking
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        self.headNode = node
        setupSceneNode()
    }

    /// - Tag: ARFaceGeometryUpdate
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        self.faceAnchor = anchor as? ARFaceAnchor
        let vector = self.headNode?.convertPosition(SCNVector3Zero, to: sceneview?.pointOfView) ?? SCNVector3Zero
        let length = Double(sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z))
        let distanceRange = (0.3 ... 0.6)
        let scalingRange = (3.0 ... 6.0)
        let normalizedLength = min(max((length - distanceRange.lowerBound) / (distanceRange.upperBound - distanceRange.lowerBound), 0.0), 1.0)
        let normalizedScale = 1.0 - normalizedLength
        let scaleValue = (normalizedScale * (scalingRange.upperBound - scalingRange.lowerBound)) + scalingRange.lowerBound
        computedScale = CGFloat(scaleValue)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if anchor is ARFaceAnchor {
            self.faceAnchor = nil
            self.headNode = nil
        }
    }

    /**
     return head gaze projection in 2D NDC coordinate system
     where the origin is at the center of the screen
     */
    private func updateGazeNDCLocationByARFaceAnchor(frame: ARFrame, isBlinking: Bool) -> CGPoint {

        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait

        let worldTransMtx = getFaceTransformationMatrix()

        let o_headCenter = simd_float4(0, 0, 0, 1)
        let o_headLookAtDir  = simd_float4(0, 0, 1, 0)

        let tranfMtx = worldTransMtx
        let c_headCenter = tranfMtx * o_headCenter
        let c_lookAtDir  = tranfMtx * o_headLookAtDir
        let t = (0.0 - c_headCenter[2]) / c_lookAtDir[2]
        let hitPos = c_headCenter + c_lookAtDir * t

        let hitPosNDC = SIMD2<Float>([Float(hitPos[0]), Float(hitPos[1])])
        let filteredPos = ndcSmoothingInterpolator.update(with: hitPosNDC, factor: isBlinking ? 0.05 : nil)

        let worldToSKSceneScale = Float(computedScale)
        let hitPosSKScene = filteredPos * worldToSKSceneScale
        switch orientation {
        case .portrait:
            return CGPoint(x: CGFloat(hitPosSKScene[1]), y: -CGFloat(hitPosSKScene[0]))
        case .portraitUpsideDown:
            return CGPoint(x: -CGFloat(hitPosSKScene[1]), y: CGFloat(hitPosSKScene[0]))
        case .landscapeRight:
            return CGPoint(x: CGFloat(hitPosSKScene[0]), y: CGFloat(hitPosSKScene[1]))
        case .landscapeLeft:
            return CGPoint(x: -CGFloat(hitPosSKScene[0]), y: -CGFloat(hitPosSKScene[1]))
        case .unknown:
            fallthrough
        @unknown default:
            return CGPoint(x: CGFloat(hitPosSKScene[0]), y: CGFloat(hitPosSKScene[1]) )
        }
    }

    /**
     Returns the world transformation matrix of the ARFaceAnchor node
     */
    private func getFaceTransformationMatrix() -> simd_float4x4 {
        return faceAnchor?.transform ?? .identity
    }

    /**
     Extract the scale components of the ARFaceAnchor node
    */
    private func getFaceScale() -> simd_float3 {
        let M = getFaceTransformationMatrix()
        let sx = simd_float3([M[0][0], M[0][1], M[0][2]])
        let sy = simd_float3([M[1][0], M[1][1], M[1][2]])
        let sz = simd_float3([M[2][0], M[2][1], M[2][2]])
        let s = simd_float3([simd_length(sx), simd_length(sy), simd_length(sz)])
        return s
    }

    /**
     Extract the rotation components of the ARFaceAnchor node
     */
    private func getFaceRotationMatrix() -> simd_float4x4 {
        let scale = getFaceScale()
        let mtx = getFaceTransformationMatrix()
        var (c0, c1, c2, c3) = mtx.columns
        c3 = simd_float4(0, 0, 0, 1) //zero out translation components
        c0 /= scale[0]
        c1 /= scale[1]
        c2 /= scale[2]
        return simd_float4x4(c0, c1, c2, c3)
    }

}

private func loadModelFromAsset(named assetName: String) -> SCNNode {
    let url = Bundle.main.url(forResource: assetName, withExtension: "scn", subdirectory: "GazeLib.scnassets")
    let node = SCNReferenceNode(url: url!)
    node?.load()
    return node!
}
