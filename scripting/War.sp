#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <autoexecconfig>
#include <war>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL		"http://bitbucket.toastdev.de/sourcemod-plugins/raw/master/War.txt"

#pragma semicolon 1
#pragma newdecls required


public Plugin myinfo = 
{
	name = "War",
	author = "Toast",
	description = "A war plugin for Jail",
	version = "0.0.2",
	url = "bitbucket.toastdev.de"
}

/************************
	Global Variabels
*************************/

// ConVar Handle
ConVar g_cBuy = null;
Handle g_cBuyTime = null;
Handle g_cLimitRounds = null;
Handle g_cDurationRounds = null;
Handle g_cAttackTeam = null;
Handle g_cLimitTime = null;
Handle g_cRulesTime = null;
Handle g_cShowRules = null;
Handle g_cCooldownTime = null;
Handle g_cAntiStuckTime = null;
Handle g_cDFFreezeTime = null;
Handle g_cDFBuyTime = null;
Handle g_cWarMoney = null;

// Forwards
Handle g_hWarRoundForward = null;
Handle g_hWarCooldownForward = null;
Handle g_hWarStatusChangedForward = null;
Handle g_hWarLimitForward = null;

// Integer
int g_iLimitRounds;
int g_iAttackTeam = 2;
int g_iDefenderTeam = 3;
int g_iDurationRounds = 1;
int g_iMinNoWarRounds;
int g_iWarRounds;
int g_iPlayerAccount;

// Float
float g_fCooldownTime = 0.0;
float g_fAntiStuckTime = 0.0;
float g_fBuyTime = 0.0;
float g_fLimitTime = 0.0;

// Boolean
bool g_bIsWar = false;
bool g_bBuy = false;
bool g_bShowRules = false;
bool g_bIsCooldown = false;
bool g_bDebug = true;

// Panel Handle
Handle g_hRules = null;

// Timer Handle
Handle g_hCooldownTimer = null;
Handle g_hAntiStuckTimer = null;
Handle g_hBuyTimer = null;
Handle g_hLimitTimer = null;

// Vector
float g_vSpawnPosition[3];
float g_vAttackSpawnPosition[3];

// Arrays
bool g_aPlayerThinkHook[MAXPLAYERS + 1];
bool g_aPlayerGodMode[MAXPLAYERS + 1];
bool g_aPlayerLateJoin[MAXPLAYERS + 1];
int g_aPlayerMoney[MAXPLAYERS + 1];

// WarStatus
WarStatus g_wsCurrentWarStatus = WS_WAITING;

/*
	Loading Stuff
*/

public void OnPluginStart()
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Loading Translations");
	}
	LoadTranslations("war.phrases");
	LoadTranslations("core.phrases");
	if(g_bDebug)
	{
		PrintToServer("[WAR] Setting Up ConVars");
	}
	// Handle the CVars
	g_cBuy = CreateConVar("sm_war_buy", "1", "Enable buy during war (1 = Enable / 0 = Disable)", _, true, 0.0, true, 1.0);
	g_cShowRules = AutoExecConfig_CreateConVar("sm_war_show_rules", "1", "Enable rules (1 = Enable / 0 = Disable)", _, true, 0.0, true, 1.0);
	g_cWarMoney = AutoExecConfig_CreateConVar("sm_war_money", "16000", "How much money the players get during War", _, true, 0.0);
	g_cBuyTime = AutoExecConfig_CreateConVar("sm_war_buy_time", "999", "Buytime during war (CS:GO uses seconds, CS:S uses minutes here)");
	g_cLimitRounds = AutoExecConfig_CreateConVar("sm_war_limit_rounds", "10", "Min rounds between two war rounds (<= 0 = Disable limit)");
	g_cDurationRounds = AutoExecConfig_CreateConVar("sm_war_duration_rounds", "3", "How many rounds will one war take", _, true, 1.0);
	g_cAttackTeam = AutoExecConfig_CreateConVar("sm_war_attack_team", "2", "Which team will attack / wait in the equipment room? (1 = Random (currently not working), 2 = Terrorists, 3 = Counter Terrorists)", _, true, 2.0, true, 3.0);
	g_cLimitTime = AutoExecConfig_CreateConVar("sm_war_limit_time", "600", "Max time a war round will take ( <= 0 = Disable limit )");
	g_cRulesTime = AutoExecConfig_CreateConVar("sm_war_rules_display_time", "10", "Time in seconds the rules should be displayed");
	g_cCooldownTime = AutoExecConfig_CreateConVar("sm_war_cooldown_time", "30.0", "Time in seconds the war starts after round start");
	g_cAntiStuckTime = AutoExecConfig_CreateConVar("sm_war_antistuck_time", "3.0", "Time in seconds antistuck will be enabled");
	g_cDFFreezeTime = FindConVar("mp_freezetime");
	g_cDFBuyTime = FindConVar("mp_buytime");

	HookConVarChange(g_cBuy, ConVarChanged);
	HookConVarChange(g_cDurationRounds, ConVarChanged);
	HookConVarChange(g_cAttackTeam, ConVarChanged);
	HookConVarChange(g_cLimitRounds, ConVarChanged);
	HookConVarChange(g_cDFBuyTime, ConVarChanged);

	// Create Forwards
	g_hWarCooldownForward = CreateGlobalForward("WAR_OnCooldown", ET_Ignore);
	g_hWarRoundForward = CreateGlobalForward("WAR_OnWarRound", ET_Ignore, Param_Cell);
	g_hWarStatusChangedForward = CreateGlobalForward("WAR_OnStatusChanged", ET_Ignore, Param_Any, Param_Any);
	g_hWarLimitForward = CreateGlobalForward("WAR_OnTimeLimit", ET_Ignore);


	if(g_bDebug)
	{
		PrintToServer("[WAR] Execute config");
	}

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();

	UpdateAllSettings();

	RegPluginLibrary("war");

	// Event Hooks
	HookEvent("round_end", Event_RoundEnd_Callback);
	HookEvent("round_start", Event_RoundStart_Callback);
	HookEvent("player_connect", Event_PlayerConnect_Callback);
	HookEvent("player_disconnect", Event_PlayerDisconnect_Callback);
	HookEvent("player_spawn", Event_PlayerSpawn_Callback);
	HookEvent("player_death", Event_PlayerDeath_Callback);

	// Offsets
	g_iPlayerAccount = FindSendPropOffs("CCSPlayer", "m_iAccount");

	if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnMapStart()
{
	FindCTSpawnPosition();
}

public APLRes AskPluginLoad2(Handle myself,bool late, char[] error, int err_max)
{
   CreateNative("WAR_SetStatus", Native_Set_Status);
   CreateNative("WAR_SetMinNoWarRounds", Native_Set_MinNoWarRounds);
   CreateNative("WAR_SetWarRounds", Native_Set_WarRounds);
   CreateNative("WAR_IsCooldown", Native_Is_Cooldown);
   CreateNative("WAR_IsWar", Native_Is_War);
   CreateNative("WAR_IsInit", Native_Is_Init);
   CreateNative("WAR_GetRounds", Native_Get_WarRounds);
   CreateNative("WAR_GetMinNoWarRounds", Native_Get_MinNoWarRounds);

   MarkNativeAsOptional("Updater_AddPlugin");
   return APLRes_Success;
}

public void ConVarChanged(Handle convar, char[] oldValue, char[] newValue) 
{
	if(!strcmp(oldValue, newValue))
	{
		UpdateSetting(convar);
	}
}

/*
	Events
*/

public Action Event_RoundStart_Callback(Handle event, char[] name, bool dontBroadcast)
{
	if(g_wsCurrentWarStatus == WS_PROCESS)
	{
		if(g_iDurationRounds <= g_iWarRounds)
		{
			if(g_bDebug)
			{
				PrintToServer("[WAR] War Stopped! %i of %i War Rounds", g_iWarRounds, g_iDurationRounds);
			}
			DeactivateHooks();
			SetMoney();
			SetStatus(WS_WAITING);
		}
		else
		{
			g_iWarRounds = g_iWarRounds + 1;
		}
	}
	else
	{
		if(g_iMinNoWarRounds >= 1)
		{
			g_iMinNoWarRounds = g_iMinNoWarRounds - 1;
		}
		else if(g_iMinNoWarRounds <= 0 && g_wsCurrentWarStatus == WS_INITIALISING)
		{
			SetStatus(WS_PROCESS);
		}
	}

	if(g_bIsWar)
	{
		// This round is WAR
		if(g_bDebug)
		{
			PrintToServer("[WAR] New war round started!");
			PrintToServer("[WAR] Attacker Team: %i", g_iAttackTeam);
		}

		TeleportToWar();
		AntiStuckTeam(g_iDefenderTeam, true);

		if(g_bShowRules)
		{
			ShowRules();
		}

		if(g_bBuy)
		{
			ActivateHooks();
			SetMoney();
		}

		// Call forward
		Call_StartForward(g_hWarRoundForward);
		Call_PushCell(g_iWarRounds - 1);

		Call_Finish();
	}
}

public Action Event_RoundEnd_Callback(Handle event, char[] name, bool dontBroadcast)
{
	// Kill all active Timers
	SaveKillTimer(g_hAntiStuckTimer);
	SaveKillTimer(g_hCooldownTimer);
	SaveKillTimer(g_hLimitTimer);
}

public Action Event_PlayerDisconnect_Callback(Handle event, char[] name, bool dontBroadcast)
{
	// Someone left the game
	int p_iUserid = GetEventInt(event, "userid");
	int p_iClient = GetClientOfUserId(p_iUserid);

	// Dectivate Think Hook
	if(g_aPlayerThinkHook[p_iClient])
	{
		SDKUnhook(p_iClient, SDKHook_PostThink, SDKHook_PostThink_Callback);
		g_aPlayerThinkHook[p_iClient] = false;
	}

	// Reset money
	g_aPlayerMoney[p_iClient] = 0;

	g_aPlayerLateJoin[p_iClient] = true;
}

public Action Event_PlayerConnect_Callback(Handle event, char[] name, bool dontBroadcast)
{
	// Someone joined the game
	int p_iUserid = GetEventInt(event, "userid");
	int p_iClient = GetClientOfUserId(p_iUserid);

	// Activate Think Hook
	if(g_bIsWar)
	{
		g_aPlayerThinkHook[p_iClient] = SDKHookEx(p_iClient, SDKHook_PostThink, SDKHook_PostThink_Callback);
	}

	g_aPlayerLateJoin[p_iClient] = true;
}

public Action Event_PlayerSpawn_Callback(Handle event, char[] name, bool dontBroadcast)
{	
	int p_iUserid = GetEventInt(event, "userid");
	int p_iClient = GetClientOfUserId(p_iUserid);

	if(g_bIsWar && g_aPlayerLateJoin[p_iClient] == true)
	{
		// oh no someone spawned lately
		if(g_bIsCooldown)
		{
			// K great you'r still okay just send you to spawn
			if(IsClientInGame(p_iClient) && GetClientTeam(p_iClient) == g_iAttackTeam)
			{
				// There you go :)
				TeleportEntity(p_iClient, g_vAttackSpawnPosition, NULL_VECTOR, NULL_VECTOR);
			}
			else if(IsClientInGame(p_iClient) && GetClientTeam(p_iClient) == g_iDefenderTeam)
			{
				TeleportEntity(p_iClient, g_vSpawnPosition, NULL_VECTOR, NULL_VECTOR);
			}
		}
		else
		{
			// :( You can't play this round :/
			ForcePlayerSuicide(p_iClient);
		}
	}
}

public Action Event_PlayerDeath_Callback(Handle event, char[] name, bool dontBroadcast)
{
	int p_iUserid = GetEventInt(event, "userid");
	int p_iClient = GetClientOfUserId(p_iUserid);

	g_aPlayerLateJoin[p_iClient] = true;
}
/*
	Hooks
*/

public void SDKHook_PostThink_Callback(int client) 
{
	// Somone started thinking? Let's confuse him!
	if(IsClientInGame(client) && IsPlayerAlive(client))
	{
		// You are in a buyzone boy! ( For sure )
		SetEntProp(client, Prop_Send, "m_bInBuyZone", 1);
	}
}

/*
	Menu Callbacks
*/

public int PanelCallback_Rules(Menu menu, MenuAction action, int param1, int param2)
{
	// Nothing
}

/*
	Timer Callbacks
*/

public Action Timer_DisableAntiStuck(Handle p_hTimer, any team)
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Stopping anti stuck after %f seconds for team: %i!", g_fAntiStuckTime, team);
	}
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team)
		{
			SetEntProp(i, Prop_Data, "m_CollisionGroup", 5);
		}
	}

	g_hAntiStuckTimer = null;
}

public Action Timer_Cooldown(Handle p_hTimer)
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Attacker team is getting free now!");
		PrintToServer("[WAR] Starting anti stuck!");
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == g_iAttackTeam)
		{
			AntiStuckTeam(g_iAttackTeam, false);
			SetEntityMoveType(i, MOVETYPE_WALK);
		}
	}

	AntiStuckTeam(g_iAttackTeam, false);
	g_bIsCooldown = false;
	CheckGodMode(true);
	g_hLimitTimer = CreateTimer(GetConVarFloat(g_cLimitTime), Timer_Limit);

	// Call forward
	Call_StartForward(g_hWarCooldownForward);
	Call_Finish();

	g_hCooldownTimer = null;
}

public Action Timer_Limit(Handle p_hTimer)
{
	// Kill all players
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i))
		{
			ForcePlayerSuicide(i);
		}
	}

	// Call forward
	Call_StartForward(g_hWarLimitForward);
	Call_Finish();

	g_hLimitTimer = null;
}

/*
	Natives
*/

public int Native_Is_War(Handle plugin, int numParams)
{
	// Simply a getter function
	return g_bIsWar;	
}

public int Native_Is_Init(Handle plugin, int numParams)
{
	// Simply a getter function
	if(g_wsCurrentWarStatus == WS_INITIALISING)
	{
		return true;	
	}
	return false;
}

public int Native_Is_Cooldown(Handle plugin, int numParams)
{
	// Simply a getter function
	return g_bIsCooldown;
}

public int Native_Get_WarRounds(Handle plugin, int numParams)
{
	return g_iWarRounds;
}

public int Native_Get_MinNoWarRounds(Handle plugin, int numParams)
{
	return g_iMinNoWarRounds;
}

public int Native_Set_MinNoWarRounds(Handle plugin, int numParams)
{
	g_iMinNoWarRounds = GetNativeCell(1);
}

public int Native_Set_WarRounds(Handle plugin, int numParams)
{
	g_iWarRounds = GetNativeCell(1);
}

public int Native_Set_Status(Handle plugin, int numParams)
{
	SetStatus(GetNativeCell(1));
}


/***************
	Private
	Functions
****************/


/*
	Settings
*/

void UpdateSetting(Handle convar = null){
	if(g_bDebug)
	{
		PrintToServer("[WAR] A ConVar changed");
	}
	else if(convar == g_cBuy)
	{
		g_bBuy = GetConVarBool(g_cBuy);
	}
	else if(convar == g_cShowRules)
	{
		g_bShowRules = GetConVarBool(g_cShowRules);
		if(g_bShowRules)
		{
			PrepareRules();
		}
	}
	else if(convar == g_cLimitRounds)
	{
		g_iLimitRounds = GetConVarInt(g_cLimitRounds);
	}
	else if(convar == g_cDurationRounds)
	{
		g_iDurationRounds = GetConVarInt(g_cDurationRounds);
	}
	else if(convar == g_cAttackTeam)
	{
		g_iAttackTeam = GetConVarInt(g_cAttackTeam);
	}
	else if(convar == g_cCooldownTime)
	{
		g_fCooldownTime = GetConVarFloat(g_cCooldownTime);
	}
	else if(convar == g_cAntiStuckTime)
	{
		g_fAntiStuckTime = GetConVarFloat(g_cAntiStuckTime);
	}
	else if(convar == g_cDFBuyTime)
	{
		if(g_bIsWar)
		{
			float p_fNewVal = GetConVarFloat(g_cDFBuyTime);
			SetConVarFloat(g_cDFBuyTime, p_fNewVal);
		}
	}
}

void UpdateAllSettings()
{
	if(g_cBuy != null)
	{
		g_bBuy = GetConVarBool(g_cBuy);
	}
	if(g_cShowRules != null)
	{
		g_bShowRules = GetConVarBool(g_cShowRules);
		if(g_bShowRules)
		{
			PrepareRules();
		}
	}
	if(g_cLimitRounds != null)
	{
		g_iLimitRounds = GetConVarInt(g_cLimitRounds);
	}
	if(g_cDurationRounds != null)
	{
		g_iDurationRounds = GetConVarInt(g_cDurationRounds);
	}
	if(g_cAttackTeam != null)
	{
		g_iAttackTeam = GetConVarInt(g_cAttackTeam);
	}
	if(g_cCooldownTime != null)
	{
		g_fCooldownTime = GetConVarFloat(g_cCooldownTime);
	}
	if(g_cAntiStuckTime != null)
	{
		g_fAntiStuckTime = GetConVarFloat(g_cAntiStuckTime);
	}
}

/*
	Find Spawn for War
*/

void FindCTSpawnPosition()
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Searching for spawn");
	}
	// Find CT spawn and save it's positions
	char p_sClassName[64];
	for(int i = MaxClients; i < GetMaxEntities(); i++)
	{
		if(IsValidEdict(i) && IsValidEntity(i))
		{
			GetEdictClassname(i, p_sClassName, sizeof(p_sClassName));
			if(StrEqual("info_player_counterterrorist", p_sClassName))
			{
				// This is a CT Spawn. Save it's position!
				float p_vPosition[3];
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", p_vPosition);
				g_vSpawnPosition[0] = p_vPosition[0];
				g_vSpawnPosition[1] = p_vPosition[1];
				g_vSpawnPosition[2] = p_vPosition[2];
				g_vAttackSpawnPosition[0] = p_vPosition[0];
				g_vAttackSpawnPosition[1] = p_vPosition[1] + 45;
				g_vAttackSpawnPosition[2] = p_vPosition[2];
				if(g_bDebug)
				{
					PrintToServer("[WAR] Spawn found @ %f, %f, %f", g_vSpawnPosition[0], g_vSpawnPosition[1] , g_vSpawnPosition[2]);
				}

				break;
			}
		}
	}
}

/*
	Rules
*/

 void PrepareRules()
{
	char p_sPathConfig[PLATFORM_MAX_PATH];
	char p_sBuffer[256];
	BuildPath(Path_SM, p_sPathConfig, sizeof(p_sPathConfig), "configs/war/rules.txt");
	if(g_bDebug)
	{

		PrintToServer("[WAR] Searching for rules file @: %s", p_sPathConfig);
	}
	if(FileExists(p_sPathConfig))
	{
		if(g_hRules != null)
		{
			CloseHandle(g_hRules);
		}
		g_hRules = CreatePanel();
		Format(p_sBuffer, sizeof(p_sBuffer), "%T", "RulesTitle", LANG_SERVER);
		SetPanelTitle(g_hRules, p_sBuffer);

		Handle p_hFile = null;
		char p_sLine[256];
		p_hFile = OpenFile(p_sPathConfig, "r");
		if(g_bDebug)
		{
			PrintToServer("[WAR] Opend rules file:");
		}
		if(p_hFile != null)
		{
			while(!IsEndOfFile(p_hFile) && ReadFileLine(p_hFile, p_sLine, sizeof(p_sLine)))
			{
				DrawPanelText(g_hRules, p_sLine);
				if(g_bDebug)
				{
					PrintToServer("[WAR](Rules File) %s", p_sLine);
				}
			}
			Format(p_sBuffer, sizeof(p_sBuffer), "%T", "Exit", LANG_SERVER);
			DrawPanelItem(g_hRules, p_sBuffer);
		}
		else
		{
			// Disable rules
			SetConVarInt(g_cShowRules, 0);
			if(g_bDebug)
				{
					PrintToServer("[WAR] Couldn't open rules file! Rules disabled!");
				}
		}
	}
	else
	{
		// Disable rules
		SetConVarInt(g_cShowRules, 0);
		if(g_bDebug)
		{
			PrintToServer("[WAR] Couldn't find rules file! Rules diabled!");
		}
	}
}

void ShowRules()
{
	// We show the important rules!
	if(g_bDebug)
	{
		PrintToServer("[WAR] Showing the rules");
	}
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && (GetClientTeam(i) == 2 || GetClientTeam(i) == 3))
		{
			PrintToServer("[WAR] Showing the rules to: %N", i);
			SendPanelToClient(g_hRules, i, PanelCallback_Rules, GetConVarInt(g_cRulesTime));
		}
	}
}

/*
	Set the War status
*/

bool SetStatus(WarStatus NewWarStatus)
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Setting War Status.");
	}
	if(g_wsCurrentWarStatus == NewWarStatus)
	{
		// War Status is already set
		return true;
	}
	else if(g_wsCurrentWarStatus == WS_WAITING)
	{
		if(NewWarStatus == WS_PROCESS)
		{
			PushStatusForward(g_wsCurrentWarStatus, WS_PROCESS);
			g_wsCurrentWarStatus = WS_PROCESS;
			g_bIsWar = true;
			g_iWarRounds = 0;
			if(g_bDebug)
			{
				PrintToServer("[WAR] New Status: War is in Process");
			}
			return true;
		}
		else if(NewWarStatus == WS_INITIALISING)
		{
			if(g_iMinNoWarRounds >= 1)
			{
				PushStatusForward(g_wsCurrentWarStatus, WS_INITIALISING);
				g_wsCurrentWarStatus = WS_INITIALISING;
				if(g_bDebug)
				{
					PrintToServer("[WAR] New Status: War gets initialised");
				}
				return true;
			}
			else if(g_iMinNoWarRounds <= 0)
			{
				PushStatusForward(g_wsCurrentWarStatus, WS_PROCESS);
				g_wsCurrentWarStatus = WS_PROCESS;
				g_bIsWar = true;
				g_iWarRounds = 0;
				if(g_bDebug)
				{
					PrintToServer("[WAR] New Status: War is in Process");
				}
				return true;
			}
			return false;
		}
		return false;
	}
	else if(g_wsCurrentWarStatus == WS_INITIALISING)
	{
		if(NewWarStatus == WS_WAITING)
		{
			PushStatusForward(g_wsCurrentWarStatus, NewWarStatus);
			g_wsCurrentWarStatus =  WS_WAITING;
			if(g_bDebug)
			{
				PrintToServer("[WAR] New Status: Waiting");
			}
			return true;
		}
		else if(NewWarStatus == WS_PROCESS)
		{
			PushStatusForward(g_wsCurrentWarStatus, NewWarStatus);
			g_wsCurrentWarStatus = WS_PROCESS;
			g_bIsWar = true;
			g_iWarRounds = 0;
			if(g_bDebug)
			{
				PrintToServer("[WAR] New Status: War is in Process");
			}
			return true;
		}
		return  false;
	}
	else if(g_wsCurrentWarStatus == WS_PROCESS)
	{
		PushStatusForward(g_wsCurrentWarStatus, NewWarStatus);
		g_wsCurrentWarStatus = NewWarStatus;
		g_iMinNoWarRounds = g_iLimitRounds;
		g_bIsWar = false;
		return true;
	}
	return false;
}

void PushStatusForward(WarStatus p_wsOldStatus, WarStatus p_wsNewStatus)
{
	PrintToServer("Calling Foward: WAR_OnStatusChanged");
	Call_StartForward(g_hWarStatusChangedForward);

	Call_PushCell(p_wsOldStatus);
	Call_PushCell(p_wsNewStatus);

	Call_Finish();
}

/*
	Teleport and start timers
*/

void TeleportToWar()
{
	// Free transfer to equipment room :O
	if(g_bDebug)
	{

		PrintToServer("[WAR] Teleporting players now");
	}
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) != 0 && GetClientTeam(i) != 1)
		{

			RemoveAllWeapons(i);
			if(GetClientTeam(i) == g_iAttackTeam) 
			{
				if(g_bDebug)
				{

					PrintToServer("[WAR] Teleporting: %N to attacker spawn", i);
				}
				TeleportEntity(i, g_vAttackSpawnPosition, NULL_VECTOR, NULL_VECTOR);
				// Stop moving!
				SetEntityMoveType(i, MOVETYPE_NONE);
			}
			else
			{
				if(g_bDebug)
				{

					PrintToServer("[WAR] Teleporting: %N to normal spawn", i);
				}
				TeleportEntity(i, g_vSpawnPosition, NULL_VECTOR, NULL_VECTOR);
			}
			g_aPlayerLateJoin[i] = false;
		}
	}
	// Start the Cooldown
	g_hCooldownTimer = CreateTimer(g_fCooldownTime + GetConVarFloat(g_cDFFreezeTime), Timer_Cooldown);
	g_bIsCooldown = true;
	CheckGodMode();
}

/*
	AntiStuck timer trigger
*/

void AntiStuckTeam(int p_iTeam, bool p_bAddFreezetime = false)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == p_iTeam)
		{
			SetEntProp(i, Prop_Data, "m_CollisionGroup", 17);
		}
	}
	if(p_bAddFreezetime)
	{
		g_hAntiStuckTimer = CreateTimer(g_fAntiStuckTime + GetConVarFloat(g_cDFFreezeTime), Timer_DisableAntiStuck, p_iTeam);
	}
	else
	{
		g_hAntiStuckTimer = CreateTimer(g_fAntiStuckTime, Timer_DisableAntiStuck, p_iTeam);
	}
}

/*
	Hook triggers
*/

void ActivateHooks()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !g_aPlayerThinkHook[i])
		{
			// Now i gonna know when you think. Ha Ha !
			g_aPlayerThinkHook[i] = SDKHookEx(i, SDKHook_PostThink, SDKHook_PostThink_Callback);
		}
	}
}

void DeactivateHooks()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !g_aPlayerThinkHook[i])
		{
			// Your thoughts are unintresting :/
			SDKUnhook(i, SDKHook_PostThink, SDKHook_PostThink_Callback);
			g_aPlayerThinkHook[i] = false;
		}
	}
}

/*
	God Mode
*/

void CheckGodMode(bool p_bDeactivate = false, int p_iClient = 0, int p_iTeam = 0)
{
	if(p_bDeactivate)
	{
		if(p_iClient != 0)
		{
			if(IsValidEntity(p_iClient) && IsClientInGame(p_iClient) && g_aPlayerGodMode[p_iClient])
			{
				g_aPlayerGodMode[p_iClient] = false;
				SetEntProp(p_iClient, Prop_Data, "m_takedamage", 2, 1);
				if(g_bDebug)
				{
					PrintToServer("[WAR] Disabled GodMode for: %N", p_iClient);
				}
			}
			return;
		}

		if(p_iTeam == 2 || p_iTeam == 3)
		{
			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsValidEntity(i) && IsClientInGame(i) && g_aPlayerGodMode[i] && GetClientTeam(i) == p_iTeam)
				{
					g_aPlayerGodMode[i] = false;
					SetEntProp(i, Prop_Data, "m_takedamage", 2, 1);
					if(g_bDebug)
					{
						PrintToServer("[WAR] Disabled GodMode for: %N", i);
					}
				}
			}
			return;
		}

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidEntity(i) && IsClientInGame(i) && g_aPlayerGodMode[i])
			{
				g_aPlayerGodMode[i] = false;
				SetEntProp(i, Prop_Data, "m_takedamage", 2, 1);
				if(g_bDebug)
				{
					PrintToServer("[WAR] Disabled GodMode for: %N", i);
				}
			}
		}
		return;
	}
	if(p_iClient != 0)
	{
		if(IsValidEntity(p_iClient) && IsClientInGame(p_iClient) && !g_aPlayerGodMode[p_iClient])
		{
			g_aPlayerGodMode[p_iClient] = true;
			SetEntProp(p_iClient, Prop_Data, "m_takedamage", 0, 1);
			if(g_bDebug)
			{
				PrintToServer("[WAR] Enabled GodMode for: %N", p_iClient);
			}
		}
		return;
	}

	if(p_iTeam == 2 || p_iTeam == 3)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidEntity(i) && IsClientInGame(i) && !g_aPlayerGodMode[i] && GetClientTeam(i) == p_iTeam)
			{
				g_aPlayerGodMode[i] = true;
				SetEntProp(i, Prop_Data, "m_takedamage", 0, 1);
				if(g_bDebug)
				{
					PrintToServer("[WAR] Enabled GodMode for: %N", i);
				}
			}
		}
		return;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidEntity(i) && IsClientInGame(i) && !g_aPlayerGodMode[i])
		{
			g_aPlayerGodMode[i] = true;
			SetEntProp(i, Prop_Data, "m_takedamage", 0, 1);
			if(g_bDebug)
			{
				PrintToServer("[WAR] Enabled GodMode for: %N", i);
			}
		}
	}
}

/*
	Money
*/

void SetMoney()
{
	// Some money for the world

	if(g_bIsWar)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				if(g_aPlayerMoney[i] == 0)
				{
					g_aPlayerMoney[i] == GetEntData(i, g_iPlayerAccount);
				}
				SetEntData(i, g_iPlayerAccount, GetConVarInt(g_cWarMoney));
			}
		}
	}
	else
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				SetEntData(i, g_iPlayerAccount, g_aPlayerMoney[i]);
			}
		}
	}
}

/*
	Stocks ( From other plugins )
*/

// Credits for this go to Hosties 2 plugin author
stock void RemoveAllWeapons(int client)
{
	// No Equipment ! ( K, knive is allowed ;) )
	int wepIdx;
	for (int i; i < 4; i++)
	{
		while ((wepIdx = GetPlayerWeaponSlot(client, i)) != -1)
		{
			RemovePlayerItem(client, wepIdx);
			AcceptEntityInput(wepIdx, "Kill");
		}
	}
	GivePlayerItem(client, "weapon_knife");
}


// Credits for this go to Alliedmodders ( who made this btw? )
stock void SaveKillTimer(Handle timer)
{
    if(timer != null)
    {
        CloseHandle(timer);
        timer = null;
    }
}