import Metal
import Cocoa
import QuartzCore

var gMetalView : MetalView?

func displayLinkCallback(
    CVDisplayLink, UnsafePointer<CVTimeStamp>,
    UnsafePointer<CVTimeStamp>, CVOptionFlags,
    UnsafeMutablePointer<CVOptionFlags>,
    userPtr: UnsafeMutablePointer<Void>) -> CVReturn
{
    gMetalView?.render()
    return kCVReturnSuccess;
}

class MetalView : NSView {
    var mDisplayLinkRef : CVDisplayLinkRef?

    var mDevice : MTLDevice!

    var mDepthPixelFormat : MTLPixelFormat = MTLPixelFormat.Depth32Float
    var mDepthStateDescriptor: MTLDepthStencilDescriptor!
    var mDepthTexture : MTLTexture?
    var mDepthState: MTLDepthStencilState!

    var mStencilPixelFormat : MTLPixelFormat = MTLPixelFormat.Invalid
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

    var mFbPixelFormat : MTLPixelFormat = MTLPixelFormat.BGRA8Unorm

    var mCurrentDrawable : CAMetalDrawable?
    var mMetalLayer : CAMetalLayer!
    
    var mMvpMatrixData : [Float32] = [
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0
    ]

    func isTextureCompatible(tex1:MTLTexture?, tex2:MTLTexture) -> Bool
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

    func setupRenderPassDescriptorForTexture(texture:MTLTexture)
    {
        let colorAttachment = mRenderPassDescriptor.colorAttachments[0]
        colorAttachment.loadAction = MTLLoadAction.Clear
        colorAttachment.clearColor = MTLClearColorMake(0.0, 1.0, 0.0, 1.0)
        colorAttachment.storeAction = MTLStoreAction.Store
        colorAttachment.texture = texture

        if !isTextureCompatible(mDepthTexture, tex2:texture) {
            if mDepthPixelFormat == MTLPixelFormat.Invalid {
                return
            }
            let desc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
                mDepthPixelFormat,
                width:texture.width, height:texture.height,
                mipmapped:false)
            desc.textureType = MTLTextureType.Type2D
            desc.sampleCount = 1

            mDepthTexture = mDevice?.newTextureWithDescriptor(desc)

            let depthAttachment = mRenderPassDescriptor.depthAttachment
            depthAttachment.texture = mDepthTexture
            depthAttachment.loadAction = MTLLoadAction.Clear
            depthAttachment.storeAction = MTLStoreAction.DontCare
            depthAttachment.clearDepth = 1.0
        }
        if !isTextureCompatible(mStencilTexture, tex2:texture) {
            if mStencilPixelFormat == MTLPixelFormat.Invalid {
                return
            }
            let desc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
                mStencilPixelFormat,
                width:texture.width, height:texture.height,
                mipmapped:false)
            desc.textureType = MTLTextureType.Type2D
            desc.sampleCount = 1

            mStencilTexture = mDevice?.newTextureWithDescriptor(desc)

            let stencilAttachment = mRenderPassDescriptor.stencilAttachment
            stencilAttachment.texture = mStencilTexture
            stencilAttachment.loadAction = MTLLoadAction.Clear
            stencilAttachment.storeAction = MTLStoreAction.DontCare
            stencilAttachment.clearStencil = 0
        }
    }

    func initMetalViewContents() {
        self.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable.union(
            NSAutoresizingMaskOptions.ViewWidthSizable)

        self.wantsLayer = true
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawPolicy.OnSetNeedsDisplay

        mDevice = MTLCreateSystemDefaultDevice()
        mRenderPassDescriptor = MTLRenderPassDescriptor()

        mMetalLayer = CAMetalLayer()
        mMetalLayer.device = mDevice
        mMetalLayer.pixelFormat = mFbPixelFormat
        mMetalLayer.framebufferOnly = true
        mMetalLayer.frame = self.frame

        self.layer?.addSublayer(mMetalLayer)
        NSLog("Layer \(self.layer)")
        NSLog("mMetalLayer= \(mMetalLayer)")
        NSLog("mMetalLayer.frame= \(mMetalLayer.frame)")

        mCommandQueue = mDevice.newCommandQueue()
        mMvpMatrixBuffer = mDevice.newBufferWithLength(16 * 4,
            options:MTLResourceOptions.StorageModeManaged)
        mMvpMatrixBuffer.label = "transform matrix (MVP)"
        //mMvpMatrixBuffer.setPurgeableState(MTLPurgeableState.NonVolatile)

        mDepthStateDescriptor = MTLDepthStencilDescriptor()
        mDepthStateDescriptor.depthCompareFunction = MTLCompareFunction.Always
        mDepthStateDescriptor.depthWriteEnabled = true

        mDepthState = mDevice.newDepthStencilStateWithDescriptor(mDepthStateDescriptor!)

        mShaderLibrary = mDevice.newDefaultLibrary()
        mVertexFunc = mShaderLibrary.newFunctionWithName("testShaderVertex")
        mFragmentFunc = mShaderLibrary.newFunctionWithName("testShaderFragment")

        mRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        mRenderPipelineDescriptor.vertexFunction = mVertexFunc
        mRenderPipelineDescriptor.fragmentFunction = mFragmentFunc
        mRenderPipelineDescriptor.depthAttachmentPixelFormat = mDepthPixelFormat
        mRenderPipelineDescriptor.stencilAttachmentPixelFormat = mStencilPixelFormat
        mRenderPipelineDescriptor.colorAttachments[0].pixelFormat = mFbPixelFormat
        mRenderPipelineDescriptor.sampleCount = 1
        mRenderPipelineDescriptor.label = "Test Pipeline"
        mRenderPipelineDescriptor.rasterizationEnabled = true

        mRenderPipelineState = try! mDevice.newRenderPipelineStateWithDescriptor(mRenderPipelineDescriptor!)
    }

    func bufHandler(buf:MTLCommandBuffer) -> Void {
        //NSLog("finished command buffer \(buf)")
    }
    
    func updateUniforms() {
        mMvpMatrixBuffer.setPurgeableState(MTLPurgeableState.Empty)
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
        //mMvpMatrixBuffer = mDevice.newBufferWithBytes(mMvpMatrixData,
        //    length: sizeof(Float32) * mMvpMatrixData.count,
        //    options: MTLResourceOptions.OptionStorageModeManaged)

        let cmdBuf : MTLCommandBuffer = mCommandQueue.commandBuffer()
        let encoder : MTLRenderCommandEncoder = cmdBuf.renderCommandEncoderWithDescriptor(mRenderPassDescriptor)

        encoder.setDepthStencilState(mDepthState)
        encoder.setRenderPipelineState(mRenderPipelineState)
        encoder.setFrontFacingWinding(MTLWinding.CounterClockwise)
        encoder.setVertexBuffer(mMvpMatrixBuffer, offset: 0, atIndex: 1)
        memcpy(mMvpMatrixBuffer.contents(), &mMvpMatrixData[0], sizeof(Float32))
        mMvpMatrixBuffer.didModifyRange(NSMakeRange(0, 16 * 4))

        mRenderEncoder.encode(mDevice!, encoder:encoder)
        cmdBuf.presentDrawable(mCurrentDrawable!)
        cmdBuf.addCompletedHandler(bufHandler)
        cmdBuf.commit()
        //cmdBuf.waitUntilCompleted()
        
        NSLog("-render")
    }

    func windowResized(notification:NSNotification)
    {
        NSLog("Resized \(self.window?.contentView.bounds)")
        NSLog("Layer \(self.layer)")

        render()
    }

    override func viewDidMoveToWindow() {
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "windowResized:",
            name: NSWindowDidResizeNotification, object: self.window)
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
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    override init(frame:NSRect) {
        super.init(frame:frame)
        initMetalViewContents()

        //clear the view. the view background color is different
        //from the window background color so that we can inspect visually
        //and make sure it fills the whole window
        self.layer?.backgroundColor = CGColorCreateGenericRGB(0.0, 0.0, 0.0, 1.0)
        registerDisplayLinkCallback()
    }

    convenience init() {
        self.init(frame:CGRectZero)
    }

    required init(coder:NSCoder) {
        fatalError("NSCoding unsupported")
    }
}
