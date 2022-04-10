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
			Tags {
				"LightMode" = "ForwardBase"
			}
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog		
			#pragma target 3.0
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

			
			// https://zhuanlan.zhihu.com/p/68025039
			float3 Diffuse_Zhihu(float3 DiffuseColor, float Metallic,float vh)
			{
				float3 FF0 = lerp(unity_ColorSpaceDielectricSpec.rgb, DiffuseColor, Metallic);
				float3 F = FF0 + (1 - FF0) * exp2((-5.55473 * vh - 6.98316) * vh);
				float3 kd = (1 - F)*(1 - Metallic);

				return DiffuseColor * kd; //暂时不除pi，参考unity自己的做法https://zhuanlan.zhihu.com/p/68025039


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

			// https://zhuanlan.zhihu.com/p/68025039
			float3 fresnelSchlick_Zhihu(float3 DiffuseColor, float Metallic,float3 vh)
			{

				//unity_ColorSpaceDielectricSpec.rgb这玩意大概是float3(0.04, 0.04, 0.04)，就是个经验值
				float3 F0 = lerp(unity_ColorSpaceDielectricSpec.rgb, DiffuseColor, Metallic);
				//float3 F = lerp(pow((1 - max(vh, 0)),5), 1, F0);//是hv不是nv
				return  F0 + (1 - F0) * exp2((-5.55473 * vh - 6.98316) * vh);

	
			}

			// https://zhuanlan.zhihu.com/p/68025039
			float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
			{
				return F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
			}


			inline half3 GetFresnelTerm(half3 F0, half cosA)
			{
				half t = Pow5(1 - cosA);   // ala Schlick interpoliation
				return F0 + (1 - F0) * t;
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


				float3 diffuseColorFromTexture = _Tint * tex2D(_MainTex, i.uv);

				
				//Disney Principled BRDF : https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
				/************split line*************/

				//1. DirectLight 
				float3 diffColor = 0;
				float3 specColor = 0;
				
				//1.1 Caculate Diffuse 
				//float3 diffuseTerm = Diffuse_Burley_Disney(diffuseColorFromTexture,roughness, nv, nl, vh);				
				float3 diffuseTerm = Diffuse_Zhihu(diffuseColorFromTexture, _Metallic, vh);
				diffColor = diffuseTerm * lightColor * nl;
				//1.2 Caculate Specular
				//1.2.1 Caculate Specular D
				float DistributionTerm = DistributionGGX(nh, roughness);
				//1.2.2 Caculate Specular G
				float GeometryTerm = GeometrySmith(nl,nv,roughness);
				//1.2.3 Caculate Specular F
			    float3 F0 = float3(0.04,0.04,0.04); 
				//F0  = lerpFloat3(F0, diffuseColorFromTexture, _Metallic);
				F0 = lerp(unity_ColorSpaceDielectricSpec.rgb, diffuseColorFromTexture, _Metallic);
			    //float3 FresnelTerm  = fresnelSchlick(vh, F0);
			    float3 FresnelTerm  = fresnelSchlick_Zhihu(diffuseColorFromTexture, _Metallic ,  vh);// zhihu version



				//specColor = (DistributionTerm * GeometryTerm * FresnelTerm) / (4 * nl * nv) * lightColor * nl;
				specColor = (DistributionTerm ) / (4 * nl * nv) * lightColor * nl;
				specColor = (DistributionTerm *  GeometryTerm * FresnelTerm) / (4 * nl * nv)* lightColor * nl* GetFresnelTerm(1, lh) * UNITY_PI;//参考知乎，多乘了* FresnelTerm(1, lh) * UNITY_PI
				//specColor = (DistributionTerm * FresnelTerm) ;
				//specColor = float3(DistributionTerm, DistributionTerm, DistributionTerm);
				//specColor = float3(GeometryTerm, GeometryTerm, GeometryTerm);
				float3 DirectLightResult = diffColor + specColor;



				/************split line*************/				
				float3 Flast = fresnelSchlickRoughness(max(nv, 0.0), F0, roughness);
				float kdLast = (1 - Flast) * (1 - _Metallic);

				//2. IndirectLight
				//// 2.1 Caculate Diffuse
				float3 iblDiffuseResult = 0;

				float3 ambient = 0.03 * diffuseColorFromTexture;
				half3 ambient_contrib = ShadeSH9(float4(i.normal, 1));
				
				float3 iblDiffuseTerm = max(half3(0, 0, 0), ambient + ambient_contrib);
				iblDiffuseResult = iblDiffuseTerm * diffuseColorFromTexture * kdLast;



				

				//// 2.2 Caculate Specular
				
				float3 iblSpecularResult = 0;
				
				//// 2.2.1 Specular PartI: pre-filtered Environment map
				float mip_roughness = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness);
				float3 reflectVec = reflect(-viewDir, i.normal);

				half mip = mip_roughness * UNITY_SPECCUBE_LOD_STEPS;
				half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectVec, mip); //根据粗糙度生成lod级别对贴图进行三线性采样

				float3 iblSpecular1 = DecodeHDR(rgbm, unity_SpecCube0_HDR);

				//// 2.2.2 Specular PartII
				float2 envBDRF = tex2D(_LUT, float2(lerp(0, 0.99, nv), lerp(0, 0.99, roughness))).rg; // LUT采样
				
				float surfaceReduction = 1.0 / (roughness*roughness + 1.0); //Liner空间
				//float surfaceReduction = 1.0 - 0.28*roughness*perceptualRoughness;  //Gamma空间
				float3 SpecularResult = (DistributionTerm) / (4 * nl * nv);//不懂这里为啥还要借用直接光计算里的数据
				float oneMinusReflectivity = 1 - max(max(SpecularResult.r, SpecularResult.g), SpecularResult.b);
				float grazingTerm = saturate(_Smoothness + (1 - oneMinusReflectivity));
				float3 iblSpecular2 = surfaceReduction * FresnelLerp(F0, grazingTerm, nv);

				// conclude
				iblSpecularResult = iblSpecular1 * iblSpecular2;

				


				float3 IndirectResult = iblDiffuseResult + iblSpecularResult;
								

				float4 result = float4(DirectLightResult + IndirectResult, 1);
		

				return result;
            }
            ENDCG
        }
    }
}
