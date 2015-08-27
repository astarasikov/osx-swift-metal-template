import Metal

class QuadEncoder : RenderEncoder
{
    var mVertexBuffer : MTLBuffer?

    //a quad
    var mVerticesData : [Float32] = [
        -1.0, -1.0, 0.0, 1.0,
        -1.0, 1.0, 0.0, 1.0,
        1.0, 1.0, 0.0, 1.0,

        -1.0, -1.0, 0.0, 1.0,
        1.0, 1.0, 0.0, 1.0,
        1.0, -1.0, 0.0, 1.0,
    ]

    func encodePrimitiveData(device: MTLDevice, encoder:MTLRenderCommandEncoder)
    {
        if nil == mVertexBuffer {
            let bufLen = mVerticesData.count * sizeofValue(mVerticesData[0])
            mVertexBuffer = device.newBufferWithBytes(&mVerticesData,
                length: bufLen,
                options: MTLResourceOptions())
        }
        encoder.setVertexBuffer(mVertexBuffer, offset: 0, atIndex: 0)
    }

    func encode(device: MTLDevice, encoder:MTLRenderCommandEncoder)
    {
        encoder.pushDebugGroup("test quad");

        encodePrimitiveData(device, encoder:encoder)
        encoder.drawPrimitives(MTLPrimitiveType.Triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: 1)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }
}
