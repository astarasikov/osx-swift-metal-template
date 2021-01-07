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

    func encodePrimitiveData(_ device: MTLDevice, encoder:MTLRenderCommandEncoder)
    {
        if nil == mVertexBuffer {
            let bufLen = mVerticesData.count * MemoryLayout.size(ofValue: mVerticesData[0])
            mVertexBuffer = device.makeBuffer(bytes: &mVerticesData,
                length: bufLen,
                options: MTLResourceOptions())
        }
        encoder.setVertexBuffer(mVertexBuffer, offset: 0, index: 0)
    }

    func encode(_ device: MTLDevice, encoder:MTLRenderCommandEncoder)
    {
        encoder.pushDebugGroup("test quad");

        encodePrimitiveData(device, encoder:encoder)
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: 1)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }
}
