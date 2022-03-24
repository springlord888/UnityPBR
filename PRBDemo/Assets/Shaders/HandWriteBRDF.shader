Shader "Yeethon/HandWriteBRDF"
{
    Properties
    {
        
		_MainTex("Texture", 2D) = "white" {}
		_Tint("Tint", Color) = (1 ,1 ,1 ,1)
		[Gamma] _Metallic("Metallic", Range(0, 1)) = 0 //金属度要经过伽马校正
		_Smoothness("Smoothness", Range(0, 1)) = 0.5
		_LUT("LUT", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
			#include "UnityStandardBRDF.cginc" 

            struct appdata
            {
                float4 vertex : POSITION;
				float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
				float3 normal : TEXCOORD1;
				float3 worldPos : TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
			float4 _Tint;
			float _Metallic;
			float _Smoothness;
			sampler2D _LUT;


			/***** function tool ******/
			

			// [Burley 2012, "Physically-Based Shading at Disney"]
			// https://zhuanlan.zhihu.com/p/60977923
			float3 Diffuse_Burley_Disney(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH)
			{
				float PI = 3.14159;
				float FD90 = 0.5 + 2 * VoH * VoH * Roughness * Roughness;
				float FdV = 1 + (FD90 - 1) * Pow5(1 - NoV);
				float FdL = 1 + (FD90 - 1) * Pow5(1 - NoL);
				return DiffuseColor * ((1 / PI) * FdV * FdL);
				
			}


			//D term 
			//https://learnopengl.com/PBR/Lighting  & https://zhuanlan.zhihu.com/p/60977923
			float DistributionGGX(float NoH, float roughness)
			{
				float PI = 3.14159;
				float roughness2 = roughness * roughness;
				float NoH2 = NoH * NoH;
				float tmp = NoH2 * (roughness2 - 1) + 1;
				return roughness2 / (PI * tmp * tmp);				
			}

			/***** function tool end******/


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.normal = UnityObjectToWorldNormal(v.normal);
				o.normal = normalize(o.normal);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);


                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
				//data preparation
				i.normal = normalize(i.normal);
				float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
				float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
				float3 lightColor = _LightColor0.rgb;
				float3 halfVector = normalize(lightDir + viewDir);  

				float perceptualRoughness = 1 - _Smoothness;

				float roughness = perceptualRoughness * perceptualRoughness; //why here?
				float squareRoughness = roughness * roughness;

				float nl = max(saturate(dot(i.normal, lightDir)), 0.000001);//divide 0 exception
				float nv = max(saturate(dot(i.normal, viewDir)), 0.000001);
				float vh = max(saturate(dot(viewDir, halfVector)), 0.000001);
				float lh = max(saturate(dot(lightDir, halfVector)), 0.000001);
				float nh = max(saturate(dot(i.normal, halfVector)), 0.000001);


				fixed4 diffuseColorFromTexture = _Tint * tex2D(_MainTex, i.uv);

				
				//Disney Principled BRDF : https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
				/************split line*************/

				//1. DirectLight 
				float3 diffColor = 0;
				float3 specColor = 0;
				
				//1.1 Caculate Diffuse 
				float3 diffuseTerm = Diffuse_Burley_Disney(diffuseColorFromTexture,roughness, nv, nl, vh);				
				diffColor = diffuseTerm * lightColor * nl;
				//1.2 Caculate Specular
				//1.2.1 Caculate Specular D
				float DistributionTerm = DistributionGGX(nh, roughness);
				//1.2.2 Caculate Specular G
				//1.2.3 Caculate Specular F
				specColor = DistributionTerm / (4 * nl*nv) * lightColor * nl;
				float3 DirectLightResult = diffColor + specColor;



				/************split line*************/

				//2. IndirectLight
				float3 iblDiffuseResult = 0;
				float3 iblSpecularResult = 0;
				float3 IndirectResult = iblDiffuseResult + iblSpecularResult;

				//2.1 Caculate Diffuse
				//2.2 Caculate Specular
				

				float4 result = float4(DirectLightResult + IndirectResult, 1);

				return result;
            }
            ENDCG
        }
    }
}
