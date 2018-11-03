#pragma semicolon 1

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.2.0"

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2_stocks>

ConVar g_hYawMin;
ConVar g_hYawMax;
ConVar g_hPitchMin;
ConVar g_hPitchMax;
ConVar g_hRelative;

Handle g_hHud;
Handle g_hHud2;

int g_iClient;
int g_iTarget;
int g_iRepeat;

int g_iHeadShots;
int g_iTotalShots;

int g_iHeadshotLastTick;

float g_fStartAng[3];

public Plugin myinfo = {
	name = "Sniper Monte Carlo",
	author = PLUGIN_AUTHOR,
	description = "Headshot Distance vs. Probability via Monte Carlo Simulation",
	version = PLUGIN_VERSION,
	url = "http://github.com/geominorai/snipermc"
};

public void OnPluginStart() {
	g_hYawMin = CreateConVar("snipermc_yaw_min", "-180.0", "Min aim yaw", FCVAR_NONE);
	g_hYawMax = CreateConVar("snipermc_yaw_max", "180.0", "Max aim yaw", FCVAR_NONE);

	g_hPitchMin = CreateConVar("snipermc_pitch_min", "-90.0", "Min aim pitch", FCVAR_NONE);
	g_hPitchMax = CreateConVar("snipermc_pitch_max", "90.0", "Max aim pitch", FCVAR_NONE);
	
	g_hRelative = CreateConVar("snipermc_relative", "0", "Simulation aim relative to starting aim", FCVAR_NONE, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_snipermc", cmdSimulate, "Run simulation");

	g_hHud = CreateHudSynchronizer();
	g_hHud2 = CreateHudSynchronizer();
}

public void OnMapStart() {
	g_iClient = -1;
	g_iTarget = -1;
	g_iRepeat = 0;
}

public void OnClientDisconnect(int iClient) {
	if (iClient == g_iClient || iClient == g_iTarget) {
		g_iClient = -1;
		g_iTarget = -1;
		g_iRepeat = 0;
	}
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAng[3], int &iWeapon, int& iSubType, int& iCmdNum, int& iTickCount, int& iSeed, int iMouse[2]) {
	if (g_iClient != -1) {
		float fPos[3], fPosTarget[3];
		GetClientEyePosition(g_iClient, fPos);
		GetClientEyePosition(g_iTarget, fPosTarget);
		
		float fDist = GetVectorDistance(fPos, fPosTarget);

		SetHudTextParams(0.01, 0.01, 1.0, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(iClient, g_hHud, "Headshots: %d (%.3f%%)", g_iHeadShots, float(g_iHeadShots)/float(g_iTotalShots) * 100.0);

		SetHudTextParams(0.01, 0.05, 1.0, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(iClient, g_hHud2, "Total: %d\nDistance: %.3f", g_iTotalShots, fDist);
	}

	if (iClient == g_iClient && TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
		if (g_iRepeat > 0) {
			iButtons |= IN_ATTACK;

			if (g_hRelative.BoolValue) {
				fAng[0] = g_fStartAng[0] + GetRandomFloat(g_hPitchMin.FloatValue, g_hPitchMax.FloatValue);
				fAng[1] = g_fStartAng[1] + GetRandomFloat(g_hYawMin.FloatValue, g_hYawMax.FloatValue);

				if (fAng[0] > 90.0) {
					fAng[0] -= 90.0;
				} else if (fAng[0] < -90.0) {
					fAng[0] += 90.0;
				}

				if (fAng[1] > 180.0) {
					fAng[1] -= 180.0;
				} else if (fAng[1] < -180.0) {
					fAng[1] += 180.0;
				}
			} else {
				fAng[0] = GetRandomFloat(g_hPitchMin.FloatValue, g_hPitchMax.FloatValue);
				fAng[1] = GetRandomFloat(g_hYawMin.FloatValue, g_hYawMax.FloatValue);
			}

			iWeapon = GetPlayerWeaponSlot(g_iClient, 0);

			float fGameTime = GetGameTime();
			SetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack", fGameTime);
			SetEntPropFloat(iWeapon, Prop_Send, "m_flNextSecondaryAttack", fGameTime);

			TeleportEntity(g_iClient, NULL_VECTOR, fAng, NULL_VECTOR);

			TF2_RegeneratePlayer(g_iClient);

			// PrintToConsole(g_iClient, "%d: Aiming at (%3.1f, %3.1f)", g_iRepeatTotal-g_iRepeat, fAng[0], fAng[1]);

			return Plugin_Changed;
		}

		float fPos[3], fPosTarget[3];
		GetClientEyePosition(g_iClient, fPos);
		GetClientEyePosition(g_iTarget, fPosTarget);
		
		float fDist = GetVectorDistance(fPos, fPosTarget);

		PrintToChatAll("Simulation ended | Dist: %.3f | P(Headshot) = %d/%d = %.3f", fDist, g_iHeadShots, g_iTotalShots, float(g_iHeadShots) / float(g_iTotalShots));

		TF2_RemoveCondition(g_iClient, TFCond_Zoomed);
		SetEntityMoveType(g_iTarget, MOVETYPE_WALK);
		g_iClient = -1;
		g_iTarget = -1;
		
		fAng[0] = g_fStartAng[0];
		fAng[1] = g_fStartAng[1];

		g_iHeadshotLastTick = 0;

		return Plugin_Changed;
	} else if (iClient == g_iTarget) {
		SetEntityHealth(iClient, 500);
	}
	
	return Plugin_Continue;
}

public Action TF2_CalcIsAttackCritical(int iClient, int iWeapon, char[] sWeaponName, bool &bResult) {
	if (iClient == g_iClient) {
		g_iTotalShots++;
		g_iRepeat--;

		//PrintToServer("%5d | %5.3f: Shoot", GetGameTickCount(), GetGameTime());
	}

	return Plugin_Continue;
}

public Action Hook_TakeDamage(int iClient, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType) {
	if (iClient == g_iTarget && iDamageType & DMG_CRIT && iAttacker == g_iClient) {
		int iTick = GetGameTickCount();
		if (iTick > g_iHeadshotLastTick) {
			//PrintToChat(g_iClient, "Headshot! | P(Headshot) = %.3f", float(g_iHeadShots) / float(g_iTotalShots));
			
			g_iHeadShots++;

			//PrintToServer("%5d | %5.3f: Headshot", GetGameTickCount(), GetGameTime());

			g_iHeadshotLastTick = iTick;

			return Plugin_Changed;
		}
		
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action cmdSimulate(int iClient, int iArgC) {
	if (iArgC != 1 && iArgC != 2) {
		ReplyToCommand(iClient, "Usage: sm_snipermc <# trials> [puppet]");
		return Plugin_Handled;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	int iPuppet = iClient;
	if (iArgC == 2) {
		char sArg2[32];
		GetCmdArg(2, sArg2, sizeof(sArg2));

		int iTarget = FindTarget(iClient, sArg2, false);
		if (iTarget != -1) {
			ReplyToCommand(iClient, "Using %N as puppet", iTarget);
			iPuppet = iTarget;
		}
	}

	int iRepeat = StringToInt(sArg1);
	if (!iRepeat) {
		ReplyToCommand(iClient, "Invalid # trials");
		return Plugin_Handled;
	}

	g_iTarget = -1;
	TFTeam iTeam = view_as<TFTeam>(GetClientTeam(iPuppet));
	for (int i=1; i<MaxClients; i++) {
		if (IsClientInGame(i) && i != iPuppet) {
			TFTeam iClientTeam = view_as<TFTeam>(GetClientTeam(i));
			if (iClientTeam > TFTeam_Spectator && iClientTeam != iTeam) {
				g_iTarget = i;
			}
		}
	}

	if (g_iTarget == -1) {
		ReplyToCommand(iClient, "No suitable targetting client of opposing team");
		return Plugin_Handled;
	}

	g_iClient = iPuppet;
	g_iRepeat = iRepeat;

	SDKHook(g_iTarget, SDKHook_OnTakeDamage, Hook_TakeDamage);

	float fPos[3], fPosTarget[3];
	GetClientEyePosition(g_iClient, fPos);
	GetClientEyePosition(g_iTarget, fPosTarget);
	
	GetClientEyeAngles(g_iClient, g_fStartAng);

	float fDist = GetVectorDistance(fPos, fPosTarget);
	ReplyToCommand(iClient, "Selected %N for target (distance %f)", g_iTarget, fDist);

	TF2_SetPlayerClass(g_iClient, TFClass_Sniper);
	SetEntityMoveType(g_iTarget, MOVETYPE_NONE);
	TF2_RegeneratePlayer(g_iClient);
	
	TF2_AddCondition(g_iClient, TFCond_Zoomed);

	g_iHeadShots = 0;
	g_iTotalShots = 0;
	g_iHeadshotLastTick = 0;

	return Plugin_Handled;
}
