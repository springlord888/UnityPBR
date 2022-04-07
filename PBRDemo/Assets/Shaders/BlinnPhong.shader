Shader "Yeethon/BlinnPhong"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		[Enum(Off, 0, On, 1)] _DiffuseShadingToggle("Diffuse Shading", Float) = 1
		[Enum(Off, 0, On, 1)] _SpecularShadingToggle("Specular Shading", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
			Tags {
				"LightMode" = "ForwardBase"
			}

            CGPROGRAM

		    #pragma multi_compile DIFFUSE_SHADING


            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog



            #include "UnityCG.cginc"
			#include "UnityStandardBRDF.cginc"

		

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
				float3 worldPos : TEXCOORD2;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
			float _DiffuseShadingToggle;
			float _SpecularShadingToggle;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
				//normal to world
				o.normal = UnityObjectToWorldNormal(v.normal); // need to cinsider the object's un-uniform scale
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }


			// 参考 https://catlikecoding.com/unity/tutorials/rendering/part-4/#2.1
            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
				i.normal = normalize(i.normal);
				//col = float4(i.normal * 0.5 + 0.5, 1); //normal test
             
													   
				// light direction
				float3 lightDir = _WorldSpaceLightPos0.xyz; //directional light, this variable is the direction
				float diffuseFactor = DotClamped(lightDir, i.normal); // make sure (0,1)

				/***Diffuse Shading******/
				// consider light color and object's color 
				float3 lightColor = _LightColor0.rgb;
				float3 diffuseColor =  col * lightColor * diffuseFactor;
				diffuseColor *= _DiffuseShadingToggle;

				/***Specular Shading******/				
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
				float3 halfVector = normalize(lightDir + viewDir);
				float3 specularColor = lightColor * pow( DotClamped(halfVector, i.normal),  0.8 * 100);
				specularColor *= _SpecularShadingToggle;

				//finalColor
				float3  finalColor = diffuseColor + specularColor;
													   
				// apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);

				
                return fixed4(finalColor,1);
            }
            ENDCG
        }
    }
} 
