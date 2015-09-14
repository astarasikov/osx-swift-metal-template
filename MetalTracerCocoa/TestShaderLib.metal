#include <metal_graphics>
#include <metal_matrix>
#include <metal_stdlib>

using namespace metal;

struct InterShaderData {
    float4 position [[position]];
    float4 color;
    float seed;
};

vertex InterShaderData testShaderVertex(
    constant float4 *iPosition [[buffer(0)]],
    constant float *iMVP [[buffer(1)]],
    uint vid [[vertex_id]])
{
    InterShaderData outData;
    outData.position = /**iMVP *  */ iPosition[vid];
    outData.color = outData.position;
    outData.seed = iMVP[0];
    return outData;
}

/*******************************************************************************
 * Scene description
 ******************************************************************************/
constant float3 cameraPosition = float3(1.0, 1.0, 10.0);
//constant float3 ClightPosition = float3(1.0, -1.0, 5.0);

constant float3 sphere1_pos = float3(-0.3, -0.3, 0.0);
constant float3 sphere2_pos = float3(0.2, 0.2, 0.0);
constant float3 box1_pos = float3(0.2, 0.6, 0.5);

struct DepthTestResult {
    float depth;
    float3 color;
};


static DepthTestResult dist_sphere(float3 position, float3 sphere_pos, float radius)
{
    return {
        length(position - sphere_pos) - radius,
        float3(1.0, 0.0, 0.0)
    };
}

static DepthTestResult dist_floor(float3 position) {
    return {
        position.y + 10.0,
        float3(0, sin(2 * position.x * position.y), 0.0)
    };
}

static DepthTestResult dist_round_box(float3 position,
                                      float3 box_pos,
                                      float scale) {
    float3 dd = abs(position) - box_pos;
    
    return {
        length(max(dd, 0.0)) - 0.2 * scale,
        float3(0.0, 0.0, 1.0)
    };
}

static DepthTestResult obj_union(DepthTestResult d1, DepthTestResult d2)
{
    if (d1.depth < d2.depth) {
        return d1;
    }
    else {
        return d2;
    }
}

static DepthTestResult obj_blend(DepthTestResult d1,
                                DepthTestResult d2, float3 position)
{
    float scale = smoothstep(length(position), 0.0, 1.0);
    float depth = mix(d1.depth, d2.depth, scale);
    float3 col = mix(d1.color, d2.color, scale);
    return {
        depth, col
    };
}

static DepthTestResult dist_to_scene(float3 position, float seed) {
    float s1_x = 0.5 * sin(seed / 1024.0);
    float s1_y = 0.5 * cos(seed / 1024.0);

    DepthTestResult s1 = dist_sphere(position, float3(s1_x, s1_y, s1_x * s1_y), 0.6);
    DepthTestResult s2 = dist_sphere(position, sphere2_pos, abs(0.5 * sin(seed / 2048.0)));
    DepthTestResult fl = dist_floor(position);
    
    s2.color = float3(1.0, 1.0, 0.0);
    DepthTestResult box1 = dist_round_box(position, box1_pos, s1_x);
    
    DepthTestResult d = obj_union(s1, s2);
    d = obj_union(d, box1);
    d = obj_union(d, fl);
    
    return d;
}

/*******************************************************************************
 * Ray Marching code
 ******************************************************************************/
#define NUM_STEPS 20

static constant float maxDepth = 100.0;

static inline float4 trace(InterShaderData inData)
{
    float3 position = float3(-1.0) + 2.0 * float3(inData.color.xyz);
    float3 direction = normalize(float3(position - cameraPosition));
    
    float seed = inData.seed;
    float lx = 2 * sin(seed / 256.0);
    float ly = 2 * sin(seed / 512.0);
    float3 lightPosition = float3(lx, ly, 5.0);
    
    float3 curPos = cameraPosition;
    float dSum = 1.0;
    
    DepthTestResult dTest = {};
    for (int i = 0; (i < NUM_STEPS) && (dSum <= maxDepth); i++) {
        dSum += dTest.depth;
        curPos += direction * dTest.depth;
        dTest = dist_to_scene(curPos, seed);
    }

    if (dSum > maxDepth) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    
    float2 offt = float2(-0.01, 0.0);
    float3 curPosOffseted = float3(dTest.depth) - float3(
        dist_to_scene(curPos + offt.xyy, seed).depth,
        dist_to_scene(curPos + offt.yxy, seed).depth,
        dist_to_scene(curPos + offt.yyx, seed).depth
    );
    float3 numericNormal = normalize(curPosOffseted);
    float coef = dot(numericNormal, normalize(lightPosition - curPos));
    
    float distanceAttenuation = 1.0 - (1.0 / maxDepth) * dSum;
    float3 finalColor = (coef * dTest.color + pow(coef, 32.0)) * distanceAttenuation;
    return float4(finalColor, 1.0);
}

fragment float4 testShaderFragment(
    InterShaderData inData [[stage_in]]
)
{
    return trace(inData);
}