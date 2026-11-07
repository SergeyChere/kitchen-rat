// Flat cartoon shading like the prototype (three.js MeshToonMaterial): light is quantised into a few bands.
Shader "KitchenRat/Toon"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        [HDR] _EmissionColor ("Emission", Color) = (0,0,0,0)
        _Steps ("Light bands", Range(1,6)) = 3
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200
        CGPROGRAM
        #pragma surface surf Toon fullforwardshadows
        #pragma target 3.0

        sampler2D _MainTex;
        fixed4 _Color;
        half4 _EmissionColor;
        half _Steps;

        struct Input { float2 uv_MainTex; };

        half4 LightingToon (SurfaceOutput s, half3 lightDir, half atten)
        {
            half nl = saturate(dot(s.Normal, lightDir)) * atten;
            half band = ceil(nl * _Steps) / _Steps;
            half4 c;
            c.rgb = s.Albedo * _LightColor0.rgb * band;
            c.a = s.Alpha;
            return c;
        }

        void surf (Input IN, inout SurfaceOutput o)
        {
            fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
            o.Albedo = c.rgb;
            o.Emission = _EmissionColor.rgb;
            o.Alpha = c.a;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
