import Metal

protocol RenderEncoder
{
    func encode(device: MTLDevice, encoder: MTLRenderCommandEncoder);
}