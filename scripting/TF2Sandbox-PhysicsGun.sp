#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "BattlefieldDuck"
#define PLUGIN_VERSION "4.6"

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <build>
#include <tf2_stocks>

#pragma newdecls required

public Plugin myinfo =
{
	name = "[TF2] Sandbox - Physics Gun",
	author = PLUGIN_AUTHOR,
	description = "Brings physics gun feature to tf2! (Sandbox version)",
	version = PLUGIN_VERSION,
	url = "https://github.com/BattlefieldDuck/TF2_PhysicsGun"
};

//Hide ammo count & weapon selection
#define HIDEHUD_WEAPONSELECTION	( 1<<0 )

//Physics Gun Settings
#define WEAPON_SLOT 1

#define SOUND_MODE "buttons/button15.wav"
#define SOUND_COPY "weapons/physcannon/physcannon_pickup.wav"

#define MODEL_PHYSICSLASER "materials/sprites/physbeam.vmt"
#define MODEL_HALOINDEX	"materials/sprites/halo01.vmt"
#define MODEL_PHYSICSGUNVM "models/weapons/v_superphyscannon.mdl"
#define MODEL_PHYSICSGUNWM "models/weapons/w_physics.mdl" //"models/weapons/w_superphyscannon.mdl" <- broken world model

static const int g_iPhysicsGunWeaponIndex = 423;//Choose Saxxy(423) because the player movement won't become a villager
static const int g_iPhysicsGunQuality = 1;
static const int g_iPhysicsGunLevel = 99-128;	//Level displays as 99 but negative level ensures this is unique
static const int g_iPhysicsGunColor[4] = {0, 191, 255, 255};

ConVar g_cvbCanGrabBuild;

int g_iModelIndex;
int g_iHaloIndex;
int g_iPhysicsGunVM;
int g_iPhysicsGunWM;

bool g_bPhysGunMode[MAXPLAYERS + 1];
bool g_bIN_ATTACK2[MAXPLAYERS + 1];

int g_iAimingEntityRef[MAXPLAYERS + 1]; //Aimming entity ref
int g_iGrabEntityRef[MAXPLAYERS + 1]; //Grabbing entity ref
int g_iGrabGlowRef[MAXPLAYERS + 1]; //Grabbing entity glow ref
int g_iGrabOutlineRef[MAXPLAYERS + 1]; //Grabbing entity outline ref
int g_iGrabPointRef[MAXPLAYERS + 1]; //Entity grabbing point
int g_iClientVMRef[MAXPLAYERS + 1]; //Client physics gun viewmodel ref
float g_fGrabDistance[MAXPLAYERS + 1]; //Distance between the client eye and entity grabbing point

float g_oldfEntityPos[MAXPLAYERS + 1][3];
float g_fEntityPos[MAXPLAYERS + 1][3];

float g_fRotateCD[MAXPLAYERS + 1];
float g_fCopyCD[MAXPLAYERS + 1];

public void OnPluginStart()
{
	RegAdminCmd("sm_physgun", Command_EquipPhysicsGun, 0, "Equip a Physics Gun");
	RegAdminCmd("sm_physicsgun", Command_EquipPhysicsGun, 0, "Equip a Physics Gun");
	
	g_cvbCanGrabBuild = CreateConVar("sm_tf2sb_physgun_cangrabbuild", "0", "Enable/disable grabbing buildings", 0, true, 0.0, true, 1.0);
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	AddNormalSoundHook(SoundHook);
}

public void OnMapStart()
{
	g_iModelIndex = PrecacheModel(MODEL_PHYSICSLASER);
	g_iHaloIndex = PrecacheModel(MODEL_HALOINDEX);
	g_iPhysicsGunVM = PrecacheModel(MODEL_PHYSICSGUNVM);
	g_iPhysicsGunWM = PrecacheModel(MODEL_PHYSICSGUNWM);

	PrecacheSound(SOUND_MODE);
	PrecacheSound(SOUND_COPY);

	for (int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	g_iAimingEntityRef[client] = INVALID_ENT_REFERENCE;
	g_iGrabEntityRef[client] = INVALID_ENT_REFERENCE;
	g_iGrabGlowRef[client] = INVALID_ENT_REFERENCE;
	g_iGrabOutlineRef[client] = INVALID_ENT_REFERENCE;
	g_iGrabPointRef[client] = INVALID_ENT_REFERENCE;
	g_fGrabDistance[client] = 99999.9;
	
	g_iClientVMRef[client] = INVALID_ENT_REFERENCE;
	
	g_fRotateCD[client] = 0.0;
	g_fCopyCD[client] = 0.0;
}

public Action SoundHook(int clients[64], int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char soundEntry[PLATFORM_MAX_PATH], int& seed)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && IsHoldingPhysicsGun(i))
		{
			if (StrEqual(sample, "common/wpn_denyselect.wav"))
			{
				return Plugin_Stop;
			}
		}
	}
	
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "tf_dropped_weapon"))
	{
		SDKHook(entity, SDKHook_SpawnPost, BlockPhysicsGunDrop);
	}
}

public void BlockPhysicsGunDrop(int entity)
{
	if(IsValidEntity(entity) && IsPhysicsGun(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

public Action Command_EquipPhysicsGun(int client, int args)
{
	if(client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	
	Build_PrintToChat(client, "You have equipped a Physics Gun (Sandbox version)!");
	
	//Set physics gun as Active Weapon
	int weapon = GetPlayerWeaponSlot(client, WEAPON_SLOT);
	if (IsValidEntity(weapon))
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
	}
	
	//Credits: FlaminSarge
	weapon = CreateEntityByName("tf_weapon_builder");
	if (IsValidEntity(weapon))
	{
		SetEntityModel(weapon, MODEL_PHYSICSGUNWM);
		SetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex", g_iPhysicsGunWeaponIndex);
		SetEntProp(weapon, Prop_Send, "m_bInitialized", 1);
		//Player crashes if quality and level aren't set with both methods, for some reason
		SetEntData(weapon, GetEntSendPropOffs(weapon, "m_iEntityQuality", true), g_iPhysicsGunQuality);
		SetEntData(weapon, GetEntSendPropOffs(weapon, "m_iEntityLevel", true), g_iPhysicsGunLevel);
		SetEntProp(weapon, Prop_Send, "m_iEntityQuality", g_iPhysicsGunQuality);
		SetEntProp(weapon, Prop_Send, "m_iEntityLevel", g_iPhysicsGunLevel);
		SetEntProp(weapon, Prop_Send, "m_iObjectType", 3);
		SetEntProp(weapon, Prop_Data, "m_iSubType", 3);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 0, _, 0);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 0, _, 1);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 0, _, 2);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 1, _, 3);
		SetEntProp(weapon, Prop_Send, "m_nSkin", 1);
		SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", g_iPhysicsGunWM);
		SetEntProp(weapon, Prop_Send, "m_nModelIndexOverrides", g_iPhysicsGunWM, _, 0);
		SetEntProp(weapon, Prop_Send, "m_nSequence", 0);
		
		TF2_RemoveWeaponSlot(client, WEAPON_SLOT);
		DispatchSpawn(weapon);
		EquipPlayerWeapon(client, weapon);		
	}

	return Plugin_Continue;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		TF2_RegeneratePlayer(client);
	}
}

public Action BlockWeaponSwitch(int client, int entity)
{
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	ClientSettings(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse);
	PhysGunSettings(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse);
	
	return Plugin_Continue;
}

/********************
		Stock
*********************/
bool IsHoldingPhysicsGun(int client)
{
	int iWeapon = GetPlayerWeaponSlot(client, WEAPON_SLOT);
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	return (IsValidEntity(iWeapon) && iWeapon == iActiveWeapon && IsPhysicsGun(iActiveWeapon));
}

//Credits: FlaminSarge
bool IsPhysicsGun(int entity) 
{
	if (GetEntSendPropOffs(entity, "m_iItemDefinitionIndex", true) <= 0) 
	{
		return false;
	}
	return GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex") == g_iPhysicsGunWeaponIndex
		&& GetEntProp(entity, Prop_Send, "m_iEntityQuality") == g_iPhysicsGunQuality
		&& GetEntProp(entity, Prop_Send, "m_iEntityLevel") == g_iPhysicsGunLevel;
}

bool IsEntityBuild(int entity)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	
	return (StrContains(classname, "obj_") != -1);
}

/* Physics gun function */
float[] GetClientEyePositionEx(int client)
{
	float pos[3]; 
	GetClientEyePosition(client, pos);
	
	return pos;
}

float[] GetClientEyeAnglesEx(int client)
{
	float angles[3]; 
	GetClientEyeAngles(client, angles);
	
	return angles;
}

float[] GetPointAimPosition(float pos[3], float angles[3], float maxtracedistance, int client)
{
	Handle trace = TR_TraceRayFilterEx(pos, angles, MASK_SOLID, RayType_Infinite, TraceEntityFilter, client);

	if(TR_DidHit(trace))
	{
		int entity = TR_GetEntityIndex(trace);
		if (entity > MaxClients && (Build_ReturnEntityOwner(entity) == client || CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC)))
		{
			g_iAimingEntityRef[client] = EntIndexToEntRef(entity);
			
			if (IsEntityBuild(entity) && !g_cvbCanGrabBuild.BoolValue)
			{
				g_iAimingEntityRef[client] = INVALID_ENT_REFERENCE;
			}
		}
		else g_iAimingEntityRef[client] = INVALID_ENT_REFERENCE;
		
		float endpos[3];
		TR_GetEndPosition(endpos, trace);
		
		if((GetVectorDistance(pos, endpos) <= maxtracedistance) || maxtracedistance <= 0)
		{
			CloseHandle(trace);
			return endpos;
		}
		else
		{
			float eyeanglevector[3];
			GetAngleVectors(angles, eyeanglevector, NULL_VECTOR, NULL_VECTOR);
			NormalizeVector(eyeanglevector, eyeanglevector);
			ScaleVector(eyeanglevector, maxtracedistance);
			AddVectors(pos, eyeanglevector, endpos);
			CloseHandle(trace);
			return endpos;
		}
	}
	
	CloseHandle(trace);
	return pos;
}

public bool TraceEntityFilter(int entity, int mask, int client)
{
	return (IsValidEntity(entity)
			&& entity != client
			&& entity != EntRefToEntIndex(g_iGrabEntityRef[client])
			&& entity != EntRefToEntIndex(g_iGrabPointRef[client])
			&& MaxClients < entity);
}

float[] GetAngleYOnly(const float angles[3])
{
	float fAngles[3];
	fAngles[1] = angles[1];

	return fAngles;
}

int CreateGrabPoint()
{
	int iGrabPoint = CreateEntityByName("prop_dynamic_override");//CreateEntityByName("info_target");
	DispatchKeyValue(iGrabPoint, "model", MODEL_PHYSICSGUNWM);
	SetEntPropFloat(iGrabPoint, Prop_Send, "m_flModelScale", 0.0);
	DispatchSpawn(iGrabPoint);
	
	return iGrabPoint;
}

//Credits: Alienmario
void TE_SetupBeamEnts(int ent1, int ent2, int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, float Width, float EndWidth, int FadeLength, float Amplitude, const int Color[4], int Speed, int flags)
{
	TE_Start("BeamEnts");
	TE_WriteEncodedEnt("m_nStartEntity", ent1);
	TE_WriteEncodedEnt("m_nEndEntity", ent2);
	TE_WriteNum("m_nModelIndex", ModelIndex);
	TE_WriteNum("m_nHaloIndex", HaloIndex);
	TE_WriteNum("m_nStartFrame", StartFrame);
	TE_WriteNum("m_nFrameRate", FrameRate);
	TE_WriteFloat("m_fLife", Life);
	TE_WriteFloat("m_fWidth", Width);
	TE_WriteFloat("m_fEndWidth", EndWidth);
	TE_WriteFloat("m_fAmplitude", Amplitude);
	TE_WriteNum("r", Color[0]);
	TE_WriteNum("g", Color[1]);
	TE_WriteNum("b", Color[2]);
	TE_WriteNum("a", Color[3]);
	TE_WriteNum("m_nSpeed", Speed);
	TE_WriteNum("m_nFadeLength", FadeLength);
	TE_WriteNum("m_nFlags", flags);
}

//Credits: FlaminSarge
#define EF_BONEMERGE			(1 << 0)
#define EF_NODRAW 				(1 << 5)
#define EF_BONEMERGE_FASTCULL	(1 << 7)
int CreateVM(int client, int modelindex)
{
	int ent = CreateEntityByName("tf_wearable_vm");
	if (!IsValidEntity(ent)) return -1;
	SetEntProp(ent, Prop_Send, "m_nModelIndex", modelindex);
	SetEntProp(ent, Prop_Send, "m_fEffects", EF_BONEMERGE|EF_BONEMERGE_FASTCULL);
	SetEntProp(ent, Prop_Send, "m_iTeamNum", GetClientTeam(client));
	SetEntProp(ent, Prop_Send, "m_usSolidFlags", 4);
	SetEntProp(ent, Prop_Send, "m_CollisionGroup", 11);
	DispatchSpawn(ent);
	SetVariantString("!activator");
	ActivateEntity(ent);
	TF2_EquipWearable(client, ent);
	
	return ent;
}

//Credits: FlaminSarge
Handle g_hSdkEquipWearable;
int TF2_EquipWearable(int client, int entity)
{
	if (g_hSdkEquipWearable == INVALID_HANDLE)
	{
		Handle hGameConf = LoadGameConfigFile("tf2items.randomizer");
		if (hGameConf == INVALID_HANDLE)
		{
			SetFailState("Couldn't load SDK functions. Could not locate tf2items.randomizer.txt in the gamedata folder.");
			return;
		}
		
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::EquipWearable");
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		g_hSdkEquipWearable = EndPrepSDKCall();
		if (g_hSdkEquipWearable == INVALID_HANDLE)
		{
			SetFailState("Could not initialize call for CTFPlayer::EquipWearable");
			CloseHandle(hGameConf);
			return;
		}
	}
	
	if (g_hSdkEquipWearable != INVALID_HANDLE) SDKCall(g_hSdkEquipWearable, client, entity);
}

bool HasOutline(int iEnt)
{
	int index = -1;
	while ((index = FindEntityByClassname(index, "tf_glow")) != -1)
	{
		if (GetEntPropEnt(index, Prop_Send, "m_hTarget") == iEnt)
		{
			return true;
		}
	}
	
	return false;
}

int CreateOutline(int iEnt)
{
	if(!HasOutline(iEnt))
	{
		char oldEntName[64];
		GetEntPropString(iEnt, Prop_Data, "m_iName", oldEntName, sizeof(oldEntName));
		
		char strName[126], strClass[64];
		GetEntityClassname(iEnt, strClass, sizeof(strClass));
		Format(strName, sizeof(strName), "%s%i", strClass, iEnt);
		DispatchKeyValue(iEnt, "targetname", strName);
		
		int ent = CreateEntityByName("tf_glow");
		if(IsValidEntity(ent))
		{
			DispatchKeyValue(ent, "targetname", "GrabOutline");
			DispatchKeyValue(ent, "target", strName);
			DispatchKeyValue(ent, "Mode", "0");
			
			char strColor[18];
			Format(strColor, sizeof(strColor), "%i %i %i %i", 135, 224, 230, 255);
			DispatchKeyValue(ent, "GlowColor", strColor); 
			
			DispatchSpawn(ent);
	
			AcceptEntityInput(ent, "Enable");
			
			//Change name back to old name because we don't need it anymore.
			SetEntPropString(iEnt, Prop_Data, "m_iName", oldEntName);
			
			return ent;
		}
	}
	
	return -1;
}

int CreateGlow(int client)
{
	int ent = CreateEntityByName("light_dynamic");
	if(IsValidEntity(ent))
	{
		SetVariantString("300");
		AcceptEntityInput(ent, "distance");
		
		SetVariantString("4");
		AcceptEntityInput(ent, "brightness");

		char strColor[18];
		Format(strColor, sizeof(strColor), "%i %i %i %i", g_iPhysicsGunColor[0], g_iPhysicsGunColor[1], g_iPhysicsGunColor[2], g_iPhysicsGunColor[3]);
		SetVariantString(strColor);
		AcceptEntityInput(ent, "color");

		DispatchSpawn(ent);
		
		float fpos[3];
		GetClientEyePosition(client, fpos);
		fpos[2] -= 30.0;
		TeleportEntity(ent, fpos, NULL_VECTOR, NULL_VECTOR);
		
		SetVariantString("!activator");
		AcceptEntityInput(ent, "SetParent", client);
		
		AcceptEntityInput(ent, "turnon", client, client);

		return ent;
	}
	
	return -1;
}

int Duplicator(int iEntity)
{
	//Get Value
	float fOrigin[3], fAngles[3];
	char szModel[64], szName[128], szClass[32];
	int iRed, iGreen, iBlue, iAlpha;
	
	GetEntityClassname(iEntity, szClass, sizeof(szClass));
	
	if (StrEqual(szClass, "prop_dynamic"))
	{
		szClass = "prop_dynamic_override";
	}
	else if (StrEqual(szClass, "prop_physics"))
	{
		szClass = "prop_physics_override";
	}
	
	GetEntPropString(iEntity, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
	GetEntPropVector(iEntity, Prop_Data, "m_angRotation", fAngles);
	GetEntityRenderColor(iEntity, iRed, iGreen, iBlue, iAlpha);
	GetEntPropString(iEntity, Prop_Data, "m_iName", szName, sizeof(szName));
	
	int iNewEntity = CreateEntityByName(szClass);
	if (iNewEntity > MaxClients && IsValidEntity(iNewEntity))
	{
		SetEntProp(iNewEntity, Prop_Send, "m_nSolidType", 6);
		SetEntProp(iNewEntity, Prop_Data, "m_nSolidType", 6);

		if (!IsModelPrecached(szModel))
		{
			PrecacheModel(szModel);
		}

		SetEntityModel(iNewEntity, szModel);
		TeleportEntity(iNewEntity, fOrigin, fAngles, NULL_VECTOR);
		DispatchSpawn(iNewEntity);
		SetEntData(iNewEntity, FindSendPropInfo("CBaseEntity", "m_CollisionGroup"), GetEntProp(iEntity, Prop_Data, "m_CollisionGroup", 4), 4, true);
		SetEntPropFloat(iNewEntity, Prop_Send, "m_flModelScale", GetEntPropFloat(iEntity, Prop_Send, "m_flModelScale"));
		(iAlpha < 255) ? SetEntityRenderMode(iNewEntity, RENDER_TRANSCOLOR) : SetEntityRenderMode(iNewEntity, RENDER_NORMAL);
		SetEntityRenderColor(iNewEntity, iRed, iGreen, iBlue, iAlpha);
		SetEntityRenderFx(iNewEntity, GetEntityRenderFx(iEntity));
		SetEntProp(iNewEntity, Prop_Send, "m_nSkin", GetEntProp(iEntity, Prop_Send, "m_nSkin"));
		SetEntPropString(iNewEntity, Prop_Data, "m_iName", szName);
		
		GetEntPropVector(iNewEntity, Prop_Send, "m_vecOrigin", fOrigin);
		
		PrintCenterTextAll("%f %f %f", fOrigin[0], fOrigin[1], fOrigin[2]);
		
		return iNewEntity;
	}
	
	return -1;
}

stock void ClientSettings(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	int iViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	if(IsHoldingPhysicsGun(client) && EntRefToEntIndex(g_iClientVMRef[client]) == INVALID_ENT_REFERENCE)
	{
		//Hide Original viewmodel
		SetEntProp(iViewModel, Prop_Send, "m_fEffects", GetEntProp(iViewModel, Prop_Send, "m_fEffects") | EF_NODRAW);
		 
		//Create client physics gun viewmodel
		g_iClientVMRef[client] = EntIndexToEntRef(CreateVM(client, g_iPhysicsGunVM));
	}
	//Remove client physics gun viewmodel
	else if (!IsHoldingPhysicsGun(client) && EntRefToEntIndex(g_iClientVMRef[client]) != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(EntRefToEntIndex(g_iClientVMRef[client]), "Kill");
	}
	
	if (IsHoldingPhysicsGun(client) && buttons & IN_ATTACK)
	{
		if (buttons & IN_ATTACK)
		{
			//Block weapon switch
			SDKHook(client, SDKHook_WeaponCanSwitchTo, BlockWeaponSwitch);
			SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | HIDEHUD_WEAPONSELECTION);
			
			int iTFViewModel = EntRefToEntIndex(g_iClientVMRef[client]);
			if (IsValidEntity(iTFViewModel) && GetEntProp(iTFViewModel, Prop_Send, "m_nSequence") != 1)
			{
				SetEntProp(iTFViewModel, Prop_Send, "m_nSequence", 1);
			}
			
			//Fix client eyes angles
			if (buttons & IN_RELOAD || buttons & IN_ATTACK3)
			{
				if(!(GetEntityFlags(client) & FL_FROZEN))	SetEntityFlags(client, (GetEntityFlags(client) | FL_FROZEN));
			}
			else
			{
				if(GetEntityFlags(client) & FL_FROZEN)	SetEntityFlags(client, (GetEntityFlags(client) & ~FL_FROZEN));
			}
		}
		else
		{
			int iTFViewModel = EntRefToEntIndex(g_iClientVMRef[client]);
			if (IsValidEntity(iTFViewModel) && GetEntProp(iTFViewModel, Prop_Send, "m_nSequence") != 0)
			{
				SetEntProp(iTFViewModel, Prop_Send, "m_nSequence", 0);
			}
		}
	}
	else
	{
		SDKUnhook(client, SDKHook_WeaponCanSwitchTo, BlockWeaponSwitch);
		
		if(GetEntProp(client, Prop_Send, "m_iHideHUD") & HIDEHUD_WEAPONSELECTION)	SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") &~HIDEHUD_WEAPONSELECTION);
		
		if(GetEntityFlags(client) & FL_FROZEN)	SetEntityFlags(client, (GetEntityFlags(client) & ~FL_FROZEN));
	}
}

stock void PhysGunSettings(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	float fPrintAngle[3];
	
	if (IsHoldingPhysicsGun(client) && (buttons & IN_ATTACK))
	{
		int iGrabPoint = EntRefToEntIndex(g_iGrabPointRef[client]);
		int iAimEntity = EntRefToEntIndex(g_iAimingEntityRef[client]);
		int iEntity = EntRefToEntIndex(g_iGrabEntityRef[client]);
		float fAimpos[3];
		fAimpos = GetPointAimPosition(GetClientEyePositionEx(client), GetClientEyeAnglesEx(client), g_fGrabDistance[client], client);

		//When the player grabbing prop
		if (iEntity != INVALID_ENT_REFERENCE && iGrabPoint != INVALID_ENT_REFERENCE && g_fGrabDistance[client] != 99999.9)
		{
			TeleportEntity(iGrabPoint, fAimpos, NULL_VECTOR, NULL_VECTOR);
			
			if (buttons & IN_RELOAD || buttons & IN_ATTACK3)
			{
				//Rotate + Push and pull
				if (buttons & IN_RELOAD)
				{
					float fAngle[3];
					GetEntPropVector(iGrabPoint, Prop_Send, "m_angRotation", fAngle);
					
					//Rotate in 45'
					if (buttons & IN_DUCK) 
					{
						if (g_fRotateCD[client] <= GetGameTime())
						{
							if (g_bPhysGunMode[client])
							{
								//Get the magnitude
								int mousex = (mouse[0] < 0) ? mouse[0]*-1 : mouse[0];
								int mousey = (mouse[1] < 0) ? mouse[1]*-1 : mouse[1];
								
								if (mousex > mousey && mousex > 5)
								{
									(mouse[0] > 0) ? (fAngle[1] += 45.0) : (fAngle[1] -= 45.0);
									
									g_fRotateCD[client] = GetGameTime() + 0.5;
								}
								else if (mousey > mousex && mousey > 5)
								{
									(mouse[1] > 0) ? (fAngle[0] -= 45.0) : (fAngle[0] += 45.0);
									
									g_fRotateCD[client] = GetGameTime() + 0.5;
								}
							}
							else
							{
								//Get the magnitude
								int mousex = (mouse[0] < 0) ? mouse[0]*-1 : mouse[0];
								int mousey = (mouse[1] < 0) ? mouse[1]*-1 : mouse[1];
								
								if (mousex > mousey && mousex > 5)
								{
									if(mouse[0] < 0)		fAngle[1] -= 45.0; //left
									else if(mouse[0] > 0)	fAngle[1] += 45.0; //right
									
									AnglesNormalize(fAngle);
									if(0.0 < fAngle[1] && fAngle[1] < 45.0)				fAngle[1] = 0.0;
									else if(45.0 < fAngle[1] && fAngle[1] < 90.0)		fAngle[1] = 45.0;
									else if(90.0 < fAngle[1] && fAngle[1] < 135.0)		fAngle[1] = 90.0;
									else if(135.0 < fAngle[1] && fAngle[1] < 180.0)		fAngle[1] = 135.0;
									else if(0.0 > fAngle[1] && fAngle[1] > -45.0)		fAngle[1] = -45.0;
									else if(-45.0 > fAngle[1] && fAngle[1] > -90.0)		fAngle[1] = -90.0;
									else if(-90.0 > fAngle[1] && fAngle[1] > -135.0)	fAngle[1] = -135.0;
									else if(-135.0 > fAngle[1] && fAngle[1] > -180.0)	fAngle[1] = -180.0;		

									g_fRotateCD[client] = GetGameTime() + 0.5;
								}
								else if (mousey > mousex && mousey > 5)
								{
									if(mouse[1] < 0) fAngle[0] -= 45.0; //Up
									else if(mouse[1] > 0) fAngle[0] += 45.0; //Down
									
									AnglesNormalize(fAngle);
									if(0.0 < fAngle[0] && fAngle[0] < 45.0)				fAngle[0] = 0.0;
									else if(45.0 < fAngle[0] && fAngle[0] < 90.0)		fAngle[0] = 45.0;
									else if(90.0 < fAngle[0] && fAngle[0] < 135.0)		fAngle[0] = 90.0;
									else if(135.0 < fAngle[0] && fAngle[0] < 180.0)		fAngle[0] = 135.0;							
									else if(180.0 < fAngle[0] && fAngle[0] < 225.0)		fAngle[0] = 180.0;
									else if(225.0 < fAngle[0] && fAngle[0] < 270.0)		fAngle[0] = 225.0;								
									else if(0.0 > fAngle[0] && fAngle[0] > -45.0)		fAngle[0] = -45.0;
									else if(-45.0 > fAngle[0] && fAngle[0] > -90.0)		fAngle[0] = -90.0;
									
									g_fRotateCD[client] = GetGameTime() + 0.5;
								}
							}							
						}
					}
					//Normal rotation
					else
					{
						fAngle[0] -= float(mouse[1]) / 6.0;
						fAngle[1] += float(mouse[0]) / 6.0;
					}
					
					AnglesNormalize(fAngle);
					
					if (g_bPhysGunMode[client])
					{
						//Set Grab point angles
						DispatchKeyValueVector(iGrabPoint, "angles", fAngle);
						
						//Unstick
						AcceptEntityInput(iEntity, "ClearParent");
						
						//Get angles after ClearParent
						GetEntPropVector(iEntity, Prop_Send, "m_angRotation", fPrintAngle);
						
						//Reset angles
						DispatchKeyValueVector(iGrabPoint, "angles", GetAngleYOnly(angles));
						
						//Stick
						SetVariantString("!activator");
						AcceptEntityInput(iEntity, "SetParent", iGrabPoint);
					}
					else
					{
						//Set Grab point angles
						DispatchKeyValueVector(iGrabPoint, "angles", fAngle);
						
						//Get Grab point angles
						GetEntPropVector(iGrabPoint, Prop_Send, "m_angRotation", fPrintAngle);
					}
					
					//Push and pull
					if(buttons & IN_FORWARD)
					{
						g_fGrabDistance[client] += 1.0;
					}				
					if(buttons & IN_BACK)
					{
						g_fGrabDistance[client] -= 1.0;
						if (g_fGrabDistance[client] < 50.0) g_fGrabDistance[client] = 50.0;
					}
				}
				//Push and pull
				else if (buttons & IN_ATTACK3)
				{
					g_fGrabDistance[client] -= mouse[1]/2.0;
					if (g_fGrabDistance[client] < 50.0) g_fGrabDistance[client] = 50.0;
				}
			}
			else
			{
				if (g_bPhysGunMode[client])
				{
					DispatchKeyValueVector(iGrabPoint, "angles", GetAngleYOnly(angles));
				}
			}
			
			if (impulse == 201)
			{
				if(g_fCopyCD[client] <= GetGameTime())
				{
					g_fCopyCD[client] = GetGameTime() + 1.0;
					
					//Unstick
					AcceptEntityInput(iEntity, "ClearParent");
					
					int iPasteEntity = Duplicator(iEntity);
					if (IsValidEntity(iPasteEntity))
					{
						if (Build_RegisterEntityOwner(iPasteEntity, Build_ReturnEntityOwner(iEntity)))
						{
							EmitSoundToAll(SOUND_COPY, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8);
						}
						else
						{
							AcceptEntityInput(iPasteEntity, "Kill");
						}
					}
					
					//Stick
					SetVariantString("!activator");
					AcceptEntityInput(iEntity, "SetParent", iGrabPoint);		
				}
			}
		}
		
		//Set beam
		if (iGrabPoint == INVALID_ENT_REFERENCE)
		{
			g_iGrabPointRef[client] = EntIndexToEntRef(CreateGrabPoint());
		}
		else
		{
			//DispatchKeyValueVector(iGrabPoint, "origin", fAimpos);
			TeleportEntity(iGrabPoint, fAimpos, NULL_VECTOR, NULL_VECTOR);
			
			int clientvm = EntRefToEntIndex(g_iClientVMRef[client]);
			if (clientvm != INVALID_ENT_REFERENCE)
			{
				int beamspeed = 10;
				float beamwidth = 0.2;
				if (iEntity != INVALID_ENT_REFERENCE)
				{
					beamwidth = 0.5;
					beamspeed = 20;
				}
				
				TE_SetupBeamEnts(iGrabPoint, clientvm, g_iModelIndex, g_iHaloIndex, 0, 10, 0.1, beamwidth, beamwidth, 0, 0.0, g_iPhysicsGunColor, beamspeed, 20);
				TE_SendToClient(client);
				
				for (int i = 1; i <= MaxClients; i++)
				{
					if (client != i && IsClientInGame(i))
					{
						int iWeaponWM = GetPlayerWeaponSlot(client, WEAPON_SLOT);
						if (IsValidEntity(iWeaponWM))
						{
							TE_SetupBeamEnts(iGrabPoint, iWeaponWM, g_iModelIndex, g_iHaloIndex, 0, 10, 0.1, beamwidth, beamwidth, 0, 0.0, g_iPhysicsGunColor, beamspeed, 20);
						}
						else
						{
							TE_SetupBeamEnts(iGrabPoint, client, g_iModelIndex, g_iHaloIndex, 0, 10, 0.1, beamwidth, beamwidth, 0, 0.0, g_iPhysicsGunColor, beamspeed, 20);
						}
						
						TE_SendToClient(i);
					}
				}
			}
			
			g_oldfEntityPos[client] = g_fEntityPos[client];
			g_fEntityPos[client] = fAimpos;
			
			TeleportEntity(iGrabPoint, fAimpos, NULL_VECTOR, NULL_VECTOR);
		}
		
		//When the player aim the prop
		if (iAimEntity != INVALID_ENT_REFERENCE && iEntity == INVALID_ENT_REFERENCE && iGrabPoint != INVALID_ENT_REFERENCE)
		{	
			//Set the aimming entity to grabbing entity
			g_iGrabEntityRef[client] = g_iAimingEntityRef[client];
			iEntity = EntRefToEntIndex(g_iGrabEntityRef[client]);
			
			//DispatchKeyValueVector(iGrabPoint, "origin", fAimpos);
			if (g_bPhysGunMode[client])
			{
				DispatchKeyValueVector(iGrabPoint, "angles", GetAngleYOnly(angles));
			}
			else
			{
				float fAngle[3];
				GetEntPropVector(iEntity, Prop_Send, "m_angRotation", fAngle);
				DispatchKeyValueVector(iGrabPoint, "angles", fAngle);
			}
			
			TeleportEntity(iGrabPoint, fAimpos, NULL_VECTOR, NULL_VECTOR);
			
			char szClass[32];
			GetEdictClassname(iEntity, szClass, sizeof(szClass));	
			if((StrEqual(szClass, "prop_physics") || StrEqual(szClass, "tf_dropped_weapon")))
			{
				float dummy[3];
				TeleportEntity(iEntity, NULL_VECTOR, NULL_VECTOR, dummy);
			}
			
			//Set entity Outline
			int outline = CreateOutline(iEntity);
			if (IsValidEntity(outline))
			{
				g_iGrabOutlineRef[client] = EntIndexToEntRef(outline);
			}
			
			//Set physgun glow
			int iGrabGlow = EntRefToEntIndex(g_iGrabGlowRef[client]); 
			if (iGrabGlow == INVALID_ENT_REFERENCE)
			{
				g_iGrabGlowRef[client] = EntIndexToEntRef(CreateGlow(client));
			}
				
			g_fGrabDistance[client] = GetVectorDistance(GetClientEyePositionEx(client), fAimpos);
			
			g_fEntityPos[client] = fAimpos;
			
			//Set grabbing entity parent to grabbing point
			SetVariantString("!activator");
			AcceptEntityInput(iEntity, "SetParent", iGrabPoint);
		}
	}
	else
	{
		int entity = EntRefToEntIndex(g_iGrabEntityRef[client]);
		if(entity != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(entity, "ClearParent");
			
			//Apply velocity
			char szClass[32];
			GetEdictClassname(entity, szClass, sizeof(szClass));
			if((StrEqual(szClass, "prop_physics") || StrEqual(szClass, "tf_dropped_weapon")))
			{
				float vector[3];
				MakeVectorFromPoints(g_oldfEntityPos[client], g_fEntityPos[client], vector);
				if (StrEqual(szClass, "prop_physics"))
				{
					ScaleVector(vector, 20.0);
				}
				else
				{
					ScaleVector(vector, 30.0);
				}
				
				TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vector);
			}
			
			g_iGrabEntityRef[client] = INVALID_ENT_REFERENCE;
		}
		else
		{
			int iGrabPoint = EntRefToEntIndex(g_iGrabPointRef[client]);
			if(iGrabPoint != INVALID_ENT_REFERENCE)
			{
				RequestFrame(KillGrabPointPost, g_iGrabPointRef[client]);
			}
		}

		int iGrabOutline = EntRefToEntIndex(g_iGrabOutlineRef[client]);
		if (iGrabOutline != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(iGrabOutline, "Kill");
		}
		
		int iGrabGlow = EntRefToEntIndex(g_iGrabGlowRef[client]);
		if (iGrabGlow != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(iGrabGlow, "Kill");
		}
		
		g_fGrabDistance[client] = 99999.9;
	}
	
	if (IsHoldingPhysicsGun(client))
	{
		if (!(buttons & IN_ATTACK))
		{
			if (buttons & IN_ATTACK2)
			{
				if (!g_bIN_ATTACK2[client])
				{
					g_bIN_ATTACK2[client] = true;
					
					g_bPhysGunMode[client] = !g_bPhysGunMode[client];
					
					EmitSoundToClient(client, SOUND_MODE);
					
					if (g_bPhysGunMode[client]) 
					{
						int iGrabPoint = EntRefToEntIndex(g_iGrabPointRef[client]);
						int iEntity = EntRefToEntIndex(g_iGrabEntityRef[client]);	
						if (iGrabPoint != INVALID_ENT_REFERENCE && iEntity != INVALID_ENT_REFERENCE)
						{
							//Unstick
							AcceptEntityInput(iEntity, "ClearParent");
							
							//Reset angles
							DispatchKeyValueVector(iGrabPoint, "angles", GetAngleYOnly(angles));
							
							//Stick
							SetVariantString("!activator");
							AcceptEntityInput(iEntity, "SetParent", iGrabPoint);
						}
					}
				}
			}
			else
			{
				g_bIN_ATTACK2[client] = false;
			}
		}
		
		if (!(buttons & IN_SCORE))
		{
			char strMode[50];
			strMode = (g_bPhysGunMode[client]) ? "Garry's Mod" : "TF2Sandbox";
			
			SetHudTextParams(0.75, 0.45, 0.05, g_iPhysicsGunColor[0], g_iPhysicsGunColor[1], g_iPhysicsGunColor[2], g_iPhysicsGunColor[3], 0, 0.0, 0.0, 0.0);

			int iEntity = EntRefToEntIndex(g_iGrabEntityRef[client]);
			if (iEntity != INVALID_ENT_REFERENCE)
			{
				if (buttons & IN_RELOAD)
				{
					ShowHudText(client, -1, "MODE: %s\n\nAngles: %i %i %i", strMode, RoundFloat(fPrintAngle[0]), RoundFloat(fPrintAngle[1]), RoundFloat(fPrintAngle[2]));
				}
				else
				{
					char strClassname[64];
					GetEntityClassname(iEntity, strClassname, sizeof(strClassname));
					
					int owner = Build_ReturnEntityOwner(iEntity);
					if (owner > 0 && owner <= MaxClients)
					{
						ShowHudText(client, -1, "MODE: %s\n\nObject: %s\nName: %s\nOwner: %N", strMode, strClassname, GetEntityName(iEntity), owner);
					}
					else
					{
						ShowHudText(client, -1, "MODE: %s\n\nObject: %s\nName: %s\nOwner: Unknown", strMode, strClassname, GetEntityName(iEntity));
					}
				}
			}
			else
			{
				ShowHudText(client, -1, "MODE: %s\n\n[MOUSE2] Change Mode\n[MOUSE1] Grab\n[MOUSE3] Pull/Push\n[R] Rotate\n[R]+[CTRL] Rotate 45*\n[T] Smart Copy", strMode);
			}
		}
	}
}

public void KillGrabPointPost(int iGrabPointRef)
{
	int iGrabPoint = EntRefToEntIndex(iGrabPointRef);
	if(iGrabPoint != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iGrabPoint, "Kill");
	}
}

char[] GetEntityName(int entity)
{
	char strName[128];
	GetEntPropString(entity, Prop_Data, "m_iName", strName, sizeof(strName));
	ReplaceString(strName, sizeof(strName), "\n", "");

	return strName;
}

void AnglesNormalize(float vAngles[3])
{
	while (vAngles[0] > 89.0)vAngles[0] -= 360.0;
	while (vAngles[0] < -89.0)vAngles[0] += 360.0;
	while (vAngles[1] > 180.0)vAngles[1] -= 360.0;
	while (vAngles[1] < -180.0)vAngles[1] += 360.0;
	while (vAngles[2] < -0.0)vAngles[2] += 360.0;
	while (vAngles[2] >= 360.0)vAngles[2] -= 360.0;
}