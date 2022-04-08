Shader "Yeethon/UnityBRDF"
{
	//Reference: https://zhuanlan.zhihu.com/p/68025039
    Properties
    {
		_Tint("Tint", Color) = (1 ,1 ,1 ,1)
        _MainTex ("Texture", 2D) = "white" {}
		[Gamma] _Metallic("Metallic", Range(0, 1)) = 0
		_Smoothness("Smoothness", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
			Tags {	"LightMode" = "ForwardBase"		}
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
			#include "UnityStandardBRDF.cginc"
			#include "UnityPBSLighting.cginc"
			 #pragma target 3.0
			 
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
				float3 normal : TEXCOORD1;
				float3 worldPos : TEXCOORD2;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
			float4 _Tint;
			float _Metallic;
			float _Smoothness;




            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
				o.normal = UnityObjectToWorldNormal(v.normal);
				o.normal = normalize(o.normal);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }


            fixed4 frag2 (v2f i) : SV_Target
            {
				i.normal = normalize(i.normal);
				float3 lightDir = _WorldSpaceLightPos0.xyz;
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
				float3 lightColor = _LightColor0.rgb;

				float3 specularTint;
				float oneMinusReflectivity;
				float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;
				albedo = DiffuseAndSpecularFromMetallic( // 从金属度生成漫反射颜色，镜面反射颜色等
					albedo, _Metallic, specularTint, oneMinusReflectivity
				);
				
				UnityLight light;
				light.color = lightColor;
				light.dir = lightDir;
				light.ndotl = DotClamped(i.normal, lightDir);
				UnityIndirect indirectLight;
				indirectLight.diffuse = 0;
				indirectLight.specular = 0;

				return UNITY_BRDF_PBS( //生成直接光pbr结果
					albedo, specularTint,
					oneMinusReflectivity, _Smoothness,
					i.normal, viewDir,
					light, indirectLight
				);

            }


            fixed4 frag (v2f i) : SV_Target
            {
				i.normal = normalize(i.normal);
				float3 lightDir = _WorldSpaceLightPos0.xyz; //directional light, is the direction
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
				float3 lightColor = _LightColor0.rgb;

				//extract diffuse and specular from Metallic workFlow
				float3 specularTint;
				float oneMinusReflectivity;
				float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;
				albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);// reference: https://zhuanlan.zhihu.com/p/137039291


				//direct light and Indirect light
				UnityLight light;
				light.color = lightColor;
				light.dir = lightDir;
				light.ndotl = DotClamped(i.normal, lightDir);
				UnityIndirect indirectLight;
				indirectLight.diffuse = 0; //didn't consider the indirect light
				indirectLight.specular = 0;


				//UNITY_PBS, for now, only direct light is considered. Indirect light is excluded
				fixed4 pbsColor = UNITY_BRDF_PBS( 
					albedo, specularTint,
					oneMinusReflectivity, _Smoothness,
					i.normal, viewDir,
					light, indirectLight
				);


              
                // apply fog
                return pbsColor;
            }
            ENDCG
        }
    }
}
