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
    outData.position = /*iMVP   **/ iPosition[vid];
    outData.color = outData.position;
    outData.seed = iMVP[0];
    
    return outData;
}

/*******************************************************************************
 * Scene description
 ******************************************************************************/
static constant float zoomFactor = 3.0;

static constant float3 camera_pos = float3(0.0, 1.0, 10.0);
//constant float3 sphere1_pos = float3(-0.3, -0.3, 0.0);
static constant float3 sphere2_pos = float3(0.5, -1.2, 0.0);
static constant float3 box1_pos = float3(0.2, 0.6, 0.5);
static constant float3 prism_pos = float3(-0.42, -0.92, 0.0);
static constant float3 sun_pos = float3(0.0, 0.0, -3.0);

static constant float4 bg_color = float4(0.0, 0.0, 0.05, 1.0);

struct DepthTestResult {
    float depth;
    float4 color;
};

static DepthTestResult dist_sphere(float3 position, float3 sphere_pos, float radius)
{
    return {
        length(position - sphere_pos) - radius,
        float4(1.0, 1.0, 0.0, 0.0)
    };
}

static DepthTestResult dist_sun(float3 position, float3 sphere_pos, float radius)
{
    float dist = length(position - sphere_pos) - radius;
    float color_green = (position.y - sphere_pos.y) / radius;
    float4 color = float4(1.0, color_green, 0.3, 1.0);
    
    if (position.y < sphere_pos.y) {
        float d = (sphere_pos.y - position.y) / radius;
        bool drop =
            (d < 0.05) ||
        (d >= 0.1 && d < 0.15) ||
        (d >= 0.2 && d < 0.25) ||
        (d >= 0.3 && d < 0.35) ||
        (d >= 0.4 && d < 0.55) ||
        (d >= 0.65 && d < 0.75) ||
        (d >= 0.85);
        
        if (drop) {
            color = bg_color;
        }
    }
    
    return {
        dist,
        color
    };
}

static DepthTestResult dist_floor(float3 position, float z_off) {
    float grid_step = 2;
    float grid_color = max(sin(2.0 * grid_step * position.x), sin(grid_step * (position.z + z_off)));
    grid_color = smoothstep(0.95, 1.0, grid_color);
    
    return {
        position.y + 10.0,
        float4(grid_color, 0.4, 0.8, 0.7)
    };
}

static DepthTestResult dist_prism(float3 position,
                                  float3 prism_pos,
                                  float2 h)
{
    float3 q = abs(position - prism_pos);
    return {
        max(q.y - h.y, max(q.x * sqrt(3.0) * 0.5 + q.z * 0.5, q.z) - h.x),
        float4(0.8, 0.3, 0.8, 0.0)
    };
}

static DepthTestResult dist_round_box(float3 position,
                                      float3 box_pos,
                                      float scale) {
    float3 dd = abs(position) - box_pos;
    
    return {
        length(max(dd, 0.0)) - 0.2 * scale,
        float4(0.0, 0.0, 1.0, 0.0)
    };
}

static DepthTestResult obj_union(DepthTestResult d1, DepthTestResult d2)
{
    if (d1.depth <= d2.depth) {
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
    float4 col = mix(d1.color, d2.color, scale);
    return {
        depth, col
    };
}

static float4 vhs_noise(float3 position, float seed) {
    position.y += 0.05 * sin(position.x * seed);
    float noise = 0.05 * abs(sin(80.0 * position.y));
    return float4(noise, noise, noise, 0.0);
}

static DepthTestResult dist_to_scene(float3 position, float seed) {
    float s1_x = 2.0 * sin(seed / 1024.0);
    float s1_y = 2.0 * cos(seed / 1024.0);

    DepthTestResult s1 = dist_sphere(position, float3(s1_x, s1_y, -s1_x * s1_y), 0.4);
    DepthTestResult s2 = dist_sphere(position, sphere2_pos, abs(0.5 * sin(seed / 2048.0)));
    s2.color = float4(0.0, 1.0, 1.0, 0.0);
    
    DepthTestResult s3 = dist_sun(position, sun_pos, 0.9 + 0.1 * sin(seed / 200.0));
    DepthTestResult fl = dist_floor(position, 0.05 * (seed / 10.0));
    
    //DepthTestResult box1 = dist_round_box(position, box1_pos, s1_x);
    DepthTestResult prism1 = dist_prism(position, prism_pos, float2(0.2, 0.3));
    
    DepthTestResult d = obj_union(s1, s2);
    d = obj_union(d, s3);
    //d = obj_blend(d, box1, 2.5);
    //d = obj_union(d, box1);
    d = obj_union(d, prism1);
    d = obj_union(d, fl);
    
    return d;
}

/*******************************************************************************
 * Ray Marching code
 ******************************************************************************/
#define NUM_STEPS 80
static constant float maxDepth = 50.0;

static inline float4 trace(InterShaderData inData)
{
    float3 position = zoomFactor * float3(inData.color.xyz);
    float3 direction = normalize(float3(position - camera_pos));
    
    float seed = inData.seed;
    float lx = 2 * sin(seed / 256.0);
    float ly = 2 * sin(seed / 512.0);
    float3 lightPosition = float3(lx, ly, 5.0);
    
    float3 curPos = camera_pos;
    float dSum = 1.0;
    
    DepthTestResult dTest = {};
    for (int i = 0; (i < NUM_STEPS) && (dSum <= maxDepth); i++) {
        dSum += dTest.depth;
        curPos += direction * dTest.depth;
        dTest = dist_to_scene(curPos, seed);

#if 0
        float2 offset = float2(0.001, 0.001);
        DepthTestResult dTest1 = dist_to_scene(curPos + float3(offset.x, offset.y, 0.0), seed);
        DepthTestResult dTest2 = dist_to_scene(curPos + float3(0, offset.y, 0.0), seed);
        DepthTestResult dTest3 = dist_to_scene(curPos + float3(offset.x, 0, 0.0), seed);
        dTest.color = 0.25 * (dTest.color + dTest1.color + dTest2.color + dTest3.color);
#endif
    }

    if (dSum > maxDepth) {
        return bg_color;
    }
    
    float2 offt = float2(-0.01, 0.0);
    float3 curPosOffseted = float3(dTest.depth) - float3(
        dist_to_scene(curPos + offt.xyy, seed).depth,
        dist_to_scene(curPos + offt.yxy, seed).depth,
        dist_to_scene(curPos + offt.yyx, seed).depth
    );
    float3 numericNormal = normalize(curPosOffseted);
    float coef = dot(numericNormal, normalize(lightPosition - curPos));
    
    if (dTest.color.w != 0.0) {
        coef = dTest.color.w;
        if (dTest.color.w == 1.0) {
            return dTest.color;
        }
    }
    
    float distanceAttenuation = 1.0 - (1.0 / maxDepth) * dSum;
    float3 finalColor = (coef * dTest.color.xyz + pow(coef, 32.0)) * distanceAttenuation;
    
    finalColor += vhs_noise(curPos, seed).xyz;
    
    return float4(finalColor, 1.0);
}

fragment float4 testShaderFragment(
    InterShaderData inData [[stage_in]]
)
{
    return trace(inData);
}
