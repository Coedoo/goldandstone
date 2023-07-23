package renderer_d3d11

screenSpaceRect_HLSL :: `
    cbuffer constants : register(b1) {
        float2 rn_screenSize;
        float2 oneOverAtlasSize;
    }

    /////////

    struct sprite {
        float2 screenPos;
        float2 size;
        float rotation;
        int2 texPos;
        int2 texSize;
        float2 pivot;
        float4 color;
    };

    struct pixel {
        float4 pos: SV_POSITION;
        float2 uv: TEX;

        float4 color: COLOR;
    };

    //////////////

    StructuredBuffer<sprite> spriteBuffer : register(t0);
    Texture2D tex : register(t1);

    SamplerState texSampler : register(s0);

    ////////////

    pixel vs_main(uint spriteId: SV_INSTANCEID, uint vertexId : SV_VERTEXID) {
        sprite sp = spriteBuffer[spriteId];

        float4 pos = float4(sp.screenPos, sp.screenPos + sp.size);
        float4 tex = float4(sp.texPos, sp.texPos + sp.texSize);

        uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };

        pixel p;

        p.pos = float4(float2(pos[i.x], pos[i.y]) * rn_screenSize - float2(1, -1), 0, 1);
        p.uv =        float2(tex[i.x], tex[i.y]) * oneOverAtlasSize;

        p.color = sp.color;

        return p;
    }

    float4 ps_main(pixel p) : SV_TARGET
    {
        float4 color = tex.Sample(texSampler, p.uv);

        if (color.a == 0) discard;

        // color.rgb *= color.a;

        return color * p.color;
    }
`

sprite_HLSL :: `
    cbuffer cameraConst : register(b0) {
        float4x4 VPMat;
    }

    cbuffer constants : register(b1) {
        float2 rn_screenSize;
        float2 oneOverAtlasSize;
    }

    /////////

    struct sprite {
        float2 pos;
        float2 size;
        float rotation;
        int2 texPos;
        int2 texSize;
        float2 pivot;
        float4 color;
    };

    struct pixel {
        float4 pos: SV_POSITION;
        float2 uv: TEX;

        float4 color: COLOR;
    };

    //////////////

    StructuredBuffer<sprite> spriteBuffer : register(t0);
    Texture2D tex : register(t1);

    SamplerState texSampler : register(s0);

    ////////////

    pixel vs_main(uint spriteId: SV_INSTANCEID, uint vertexId : SV_VERTEXID) {
        sprite sp = spriteBuffer[spriteId];

        float2 anchor = sp.pivot * sp.size;
        anchor = float2(-anchor.x, anchor.y);
        float4 pos = float4(anchor, anchor + float2(sp.size.x, -sp.size.y));
        float4 tex = float4(sp.texPos, sp.texPos + sp.texSize);

        uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };

        pixel p;

        float2x2 rot = float2x2(cos(sp.rotation), -sin(sp.rotation), 
                                sin(sp.rotation), cos(sp.rotation));
        float2 tp = mul(rot, float2(pos[i.x], pos[i.y])) + sp.pos;

        p.pos = mul(VPMat, float4(tp, 0, 1));
        p.uv  = float2(tex[i.x], tex[i.y]) * oneOverAtlasSize;

        p.color = sp.color;

        return p;
    }

    float4 ps_main(pixel p) : SV_TARGET
    {
        float4 color = tex.Sample(texSampler, p.uv);

        if (color.a == 0) discard;

        // float4 c = float4(color.rgb * p.color.rgb, color.a);
        return color * p.color;
    }
`

sdfFont_HLSL :: `
    cbuffer constants : register(b1) {
        float2 rn_screenSize;
        float2 oneOverAtlasSize;
    }

    /////////

    struct sprite {
        float2 screenPos;
        float2 size;
        float rotation;
        int2 texPos;
        int2 texSize;
        float2 pivot;
        float4 color;
    };

    struct pixel {
        float4 pos: SV_POSITION;
        float2 uv: TEX;

        float4 color: COLOR;
    };

    //////////////

    StructuredBuffer<sprite> spriteBuffer : register(t0);
    Texture2D tex : register(t1);

    SamplerState texSampler : register(s0);

    ////////////

    pixel vs_main(uint spriteId: SV_INSTANCEID, uint vertexId : SV_VERTEXID) {
        sprite sp = spriteBuffer[spriteId];

        float4 pos = float4(sp.screenPos, sp.screenPos + sp.size);
        float4 tex = float4(sp.texPos, sp.texPos + sp.texSize);

        uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };

        pixel p;

        p.pos = float4(float2(pos[i.x], pos[i.y]) * rn_screenSize - float2(1, -1), 0, 1);
        p.uv =        float2(tex[i.x], tex[i.y]) * oneOverAtlasSize;

        p.color = sp.color;

        return p;
    }

    float4 ps_main(pixel p) : SV_TARGET
    {
        const float smooth = 4.0/16.0;

        float dist = tex.Sample(texSampler, p.uv).a;
        float alpha = smoothstep(0.5 - smooth, 0.5 + smooth, dist);

        return float4(p.color.rgb, alpha);
    }
`