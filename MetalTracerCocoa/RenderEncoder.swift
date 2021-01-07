import Metal

protocol RenderEncoder
{
    func encode(_ device: MTLDevice, encoder: MTLRenderCommandEncoder);
}
