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
			float lerpFloat3(float3 from, float3 to, float factor)
			{
				float x = lerp(from.x, to.x, factor);
				float y = lerp(from.y, to.y, factor);
				float z = lerp(from.z, to.z, factor);
				return float3(x,y,z);
			}

			// [Burley 2012, "Physically-Based Shading at Disney"]
			// https://zhuanlan.zhihu.com/p/60977923
			float3 Diffuse_Burley_Disney(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH)
			{
				float PI = 3.14159;
				float FD90 = 0.5 + 2 * VoH * VoH * Roughness * Roughness;
				float FdV = 1 + (FD90 - 1) * Pow5(1 - NoV);
				float FdL = 1 + (FD90 - 1) * Pow5(1 - NoL);
				//return DiffuseColor * ((1 / PI) * FdV * FdL);
				return DiffuseColor * (1 * FdV * FdL); //暂时不除pi，参考unity自己的做法https://zhuanlan.zhihu.com/p/68025039
				
			}


			//D term 
			//https://learnopengl.com/PBR/Lighting  & https://zhuanlan.zhihu.com/p/60977923
			float DistributionGGX(float NoH, float roughness)
			{
				float PI = 3.14159;
				roughness = lerp(0.002, 1, roughness);//adjust roughness, avoid 0 roughness , this is a trick for Caculate D term
				float roughness2 = roughness * roughness;
				float NoH2 = NoH * NoH;
				float tmp = NoH2 * (roughness2 - 1) + 1;
				return roughness2 / (PI * tmp * tmp);				
			}



			// GGX_Schlick   here the k if for direct lighting, k = (rougness+1)^2 / 8
			float GeometrySchlickGGX(float NdotVorNdotL, float roughness)
			{
				float r = (roughness + 1.0);
				float k = (r*r) / 8.0;

				float num   = NdotVorNdotL;
				float denom = NdotVorNdotL * (1.0 - k) + k;
	
				return num / denom;
			}

			//G  term
			float GeometrySmith(float NdotV, float NdotL, float roughness)
			{
				float ggx2  = GeometrySchlickGGX(NdotV, roughness);
				float ggx1  = GeometrySchlickGGX(NdotL, roughness);
				return ggx1 * ggx2;
			}


			//F term cosTheta is HDotV, but some engine uses LDotH : http://filmicworlds.com/blog/optimizing-ggx-shaders-with-dotlh/
			float3 fresnelSchlick(float cosTheta, float3 F0)
			{
				return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
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
				//diffColor = diffuseTerm * lightColor * nl;
				//1.2 Caculate Specular
				//1.2.1 Caculate Specular D
				float DistributionTerm = DistributionGGX(nh, roughness);
				//1.2.2 Caculate Specular G
				float GeometryTerm = GeometrySmith(nl,nv,roughness);
				//1.2.3 Caculate Specular F
			    float3 F0 = float3(0.04,0.04,0.04); 
				F0  = lerpFloat3(F0, diffuseColorFromTexture, _Metallic);
			    float3 FresnelTerm  = fresnelSchlick(vh, F0);



				//specColor = (DistributionTerm * GeometryTerm * FresnelTerm) / (4 * nl * nv) * lightColor * nl;
				specColor = (DistributionTerm ) / (4 * nl * nv) * lightColor * nl;
				//specColor = (DistributionTerm * FresnelTerm) ;
				//specColor = float3(DistributionTerm, DistributionTerm, DistributionTerm);
				//specColor = float3(GeometryTerm, GeometryTerm, GeometryTerm);
				//specColor = FresnelTerm;
	

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
