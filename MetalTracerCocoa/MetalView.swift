import Metal
import Cocoa
import QuartzCore

var gMetalView : MetalView?

func displayLinkCallback(
    _:CVDisplayLink, _:UnsafePointer<CVTimeStamp>,
    _:UnsafePointer<CVTimeStamp>, _:CVOptionFlags,
    _:UnsafeMutablePointer<CVOptionFlags>,
    userPtr: UnsafeMutableRawPointer?) -> CVReturn
{
    gMetalView?.render()
    return kCVReturnSuccess;
}

class MetalView : NSView {
    var mDisplayLinkRef : CVDisplayLink?

    var mDevice : MTLDevice!

    var mDepthPixelFormat : MTLPixelFormat = MTLPixelFormat.depth32Float
    var mDepthStateDescriptor: MTLDepthStencilDescriptor!
    var mDepthTexture : MTLTexture?
    var mDepthState: MTLDepthStencilState!

    var mStencilPixelFormat : MTLPixelFormat = MTLPixelFormat.invalid
    var mStencilTexture : MTLTexture?

    var mCommandQueue : MTLCommandQueue!
    var mCommandEncoder: MTLRenderCommandEncoder!

    var mRenderEncoder : RenderEncoder = QuadEncoder()

    var mShaderLibrary : MTLLibrary!
    var mVertexFunc: MTLFunction!
    var mFragmentFunc: MTLFunction!

    var mMvpMatrixBuffer : MTLBuffer!

    var mRenderPipelineState: MTLRenderPipelineState!
    var mRenderPipelineDescriptor: MTLRenderPipelineDescriptor!
    var mRenderPassDescriptor:MTLRenderPassDescriptor!

    var mFbPixelFormat : MTLPixelFormat = MTLPixelFormat.bgra8Unorm

    var mCurrentDrawable : CAMetalDrawable?
    var mMetalLayer : CAMetalLayer!
    
    var mMvpMatrixData : [Float32] = [
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0
    ]

    func isTextureCompatible(_ tex1:MTLTexture?, tex2:MTLTexture) -> Bool
    {
        if nil == tex1 {
            return false
        }

        if tex1?.width != tex2.width {
            return false
        }

        if tex1?.height != tex2.height {
            return false
        }

        if tex1?.sampleCount != tex2.sampleCount {
            return false
        }
        return true
    }

    func setupRenderPassDescriptorForTexture(_ texture:MTLTexture)
    {
        let colorAttachment = mRenderPassDescriptor.colorAttachments[0]
        colorAttachment?.loadAction = MTLLoadAction.clear
        colorAttachment?.clearColor = MTLClearColorMake(0.0, 1.0, 0.0, 1.0)
        colorAttachment?.storeAction = MTLStoreAction.store
        colorAttachment?.texture = texture

        if !isTextureCompatible(mDepthTexture, tex2:texture) {
            if mDepthPixelFormat == MTLPixelFormat.invalid {
                return
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: mDepthPixelFormat,
                width:texture.width, height:texture.height,
                mipmapped:false)
            desc.textureType = MTLTextureType.type2D
            desc.sampleCount = 1
            desc.resourceOptions = MTLResourceOptions.storageModePrivate;
            desc.usage = MTLTextureUsage.renderTarget;

            mDepthTexture = mDevice?.makeTexture(descriptor: desc)

            let depthAttachment = mRenderPassDescriptor.depthAttachment
            depthAttachment?.texture = mDepthTexture
            depthAttachment?.loadAction = MTLLoadAction.clear
            depthAttachment?.storeAction = MTLStoreAction.dontCare
            depthAttachment?.clearDepth = 1.0
        }
        if !isTextureCompatible(mStencilTexture, tex2:texture) {
            if mStencilPixelFormat == MTLPixelFormat.invalid {
                return
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: mStencilPixelFormat,
                width:texture.width, height:texture.height,
                mipmapped:false)
            desc.textureType = MTLTextureType.type2D
            desc.sampleCount = 1

            mStencilTexture = mDevice?.makeTexture(descriptor: desc)

            let stencilAttachment = mRenderPassDescriptor.stencilAttachment
            stencilAttachment?.texture = mStencilTexture
            stencilAttachment?.loadAction = MTLLoadAction.clear
            stencilAttachment?.storeAction = MTLStoreAction.dontCare
            stencilAttachment?.clearStencil = 0
        }
    }

    func initMetalViewContents() {
        self.autoresizingMask = NSView.AutoresizingMask.height.union(
            NSView.AutoresizingMask.width)

        self.wantsLayer = true
        self.layerContentsRedrawPolicy = NSView.LayerContentsRedrawPolicy.onSetNeedsDisplay
        
        //let devices = MTLCopyAllDevices()
        //mDevice = devices[0]
        mDevice = MTLCreateSystemDefaultDevice()
        NSLog("Device \(String(describing: mDevice))")
        mRenderPassDescriptor = MTLRenderPassDescriptor()

        mMetalLayer = CAMetalLayer()
        mMetalLayer.device = mDevice
        mMetalLayer.pixelFormat = mFbPixelFormat
        mMetalLayer.framebufferOnly = true
        mMetalLayer.frame = self.frame

        self.layer?.addSublayer(mMetalLayer)
        NSLog("Layer \(String(describing: self.layer))")
        NSLog("mMetalLayer= \(String(describing: mMetalLayer))")
        NSLog("mMetalLayer.frame= \(mMetalLayer.frame)")

        mCommandQueue = mDevice.makeCommandQueue()
        mMvpMatrixBuffer = mDevice.makeBuffer(length: 16 * 4,
            options:MTLResourceOptions.storageModeManaged)
        mMvpMatrixBuffer.label = "transform matrix (MVP)"
        //mMvpMatrixBuffer.setPurgeableState(MTLPurgeableState.NonVolatile)

        mDepthStateDescriptor = MTLDepthStencilDescriptor()
        mDepthStateDescriptor.depthCompareFunction = MTLCompareFunction.always
        mDepthStateDescriptor.isDepthWriteEnabled = true

        mDepthState = mDevice.makeDepthStencilState(descriptor: mDepthStateDescriptor!)

        mShaderLibrary = mDevice.makeDefaultLibrary()
        mVertexFunc = mShaderLibrary.makeFunction(name: "testShaderVertex")
        mFragmentFunc = mShaderLibrary.makeFunction(name: "testShaderFragment")

        mRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        mRenderPipelineDescriptor.vertexFunction = mVertexFunc
        mRenderPipelineDescriptor.fragmentFunction = mFragmentFunc
        mRenderPipelineDescriptor.depthAttachmentPixelFormat = mDepthPixelFormat
        mRenderPipelineDescriptor.stencilAttachmentPixelFormat = mStencilPixelFormat
        mRenderPipelineDescriptor.colorAttachments[0].pixelFormat = mFbPixelFormat
        mRenderPipelineDescriptor.sampleCount = 1
        mRenderPipelineDescriptor.label = "Test Pipeline"
        mRenderPipelineDescriptor.isRasterizationEnabled = true

        mRenderPipelineState = try! mDevice.makeRenderPipelineState(descriptor: mRenderPipelineDescriptor!)
    }

    func bufHandler(_ buf:MTLCommandBuffer) -> Void {
        //NSLog("finished command buffer \(buf)")
    }
    
    func updateUniforms() {
        mMvpMatrixBuffer.setPurgeableState(MTLPurgeableState.empty)
    }

    func render() {
        if nil == mCurrentDrawable {
            mCurrentDrawable = mMetalLayer.nextDrawable()
            setupRenderPassDescriptorForTexture(mCurrentDrawable!.texture)
        }
        if nil == mCurrentDrawable {
            NSLog("drawable is NIL")
            return
        }
        
        mMvpMatrixData[0] += 10.0

        let cmdBuf : MTLCommandBuffer = mCommandQueue.makeCommandBuffer()!
        let encoder : MTLRenderCommandEncoder = cmdBuf.makeRenderCommandEncoder(descriptor: mRenderPassDescriptor)!

        encoder.setDepthStencilState(mDepthState)
        encoder.setRenderPipelineState(mRenderPipelineState)
        encoder.setFrontFacing(MTLWinding.counterClockwise)
        encoder.setVertexBuffer(mMvpMatrixBuffer, offset: 0, index: 1)
        memcpy(mMvpMatrixBuffer.contents(), &mMvpMatrixData[0], MemoryLayout<Float32>.size)
        mMvpMatrixBuffer.didModifyRange(Range(uncheckedBounds: (lower: 0, upper: 16 * 4)))

        mRenderEncoder.encode(mDevice!, encoder:encoder)
        cmdBuf.present(mCurrentDrawable!)
        mCurrentDrawable = nil
        cmdBuf.addCompletedHandler(bufHandler)
        cmdBuf.commit()

        //cmdBuf.waitUntilCompleted()
        
        DispatchQueue.main.async(execute: {
                self.needsDisplay = true
            }
        )
        
        NSLog("-render")
    }

    @objc func windowResized(_ notification:Notification)
    {
        NSLog("Resized \(String(describing: self.window?.contentView?.bounds))")
        NSLog("Layer \(String(describing: self.layer))")

        render()
    }

    override func viewDidMoveToWindow() {
        /*
        NotificationCenter.default.addObserver(self,
            selector: #selector(MetalView.windowResized(_:)),
            name: NSNotification.Name.NSWindow.didResizeNotification, object: self.window)*/
    }

    func registerDisplayLinkCallback() {
        CVDisplayLinkCreateWithActiveCGDisplays(&mDisplayLinkRef)
        gMetalView = self
        CVDisplayLinkSetOutputCallback(mDisplayLinkRef!, displayLinkCallback, nil)
        CVDisplayLinkStart(mDisplayLinkRef!)
    }

    deinit {
        CVDisplayLinkStop(mDisplayLinkRef!)
        mDisplayLinkRef = nil
        NotificationCenter.default.removeObserver(self)
    }

    override init(frame:NSRect) {
        super.init(frame:frame)
        initMetalViewContents()

        //clear the view. the view background color is different
        //from the window background color so that we can inspect visually
        //and make sure it fills the whole window
        self.layer?.backgroundColor = CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        registerDisplayLinkCallback()
    }

    convenience init() {
        self.init(frame:CGRect.zero)
    }

    required init(coder:NSCoder) {
        fatalError("NSCoding unsupported")
    }
}
