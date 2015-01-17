#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <autoexecconfig>
#include <war>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL		"http://bitbucket.toastdev.de/sourcemod-plugins/raw/master/War.txt"
#define RULESCONFIG_PATH "/configs/war"
public Plugin:myinfo = 
{
	name = "War",
	author = "Toast",
	description = "A war plugin for Jail",
	version = "0.0.1",
	url = "bitbucket.toastdev.de"
}

/************************
	Global Variabels
*************************/

// ConVar Handle
new Handle:g_cBuy = INVALID_HANDLE;
new Handle:g_cBuyTime = INVALID_HANDLE;
new Handle:g_cLimitRounds = INVALID_HANDLE;
new Handle:g_cDurationRounds = INVALID_HANDLE;
new Handle:g_cAttackTeam = INVALID_HANDLE;
new Handle:g_cLimitTime = INVALID_HANDLE;
new Handle:g_cRulesTime = INVALID_HANDLE;
new Handle:g_cShowRules = INVALID_HANDLE;
new Handle:g_cCooldownTime = INVALID_HANDLE;
new Handle:g_cAntiStuckTime = INVALID_HANDLE;
new Handle:g_cDFFreezeTime = INVALID_HANDLE;
new Handle:g_cDFBuyTime = INVALID_HANDLE;
new Handle:g_cWarMoney = INVALID_HANDLE;

// Integer
new g_iBuyTime;
new g_iLimitRounds;
new g_iLimitTime;
new g_iAttackTeam = 2;
new g_iDefenderTeam = 3;
new g_iDurationRounds = 1;
new g_iRulesTime;
new g_iMinNoWarRounds;
new g_iWarRounds;
new g_iPlayerAccount;

// Float
new Float:g_fCooldownTime = 0.0;
new Float:g_fAntiStuckTime = 0.0;

// Boolean
new bool:g_bIsWar = false;
new bool:g_bBuy = false;
new bool:g_bShowRules = false;
new bool:g_bIsCooldown = false;
new bool:g_bDebug = true;

// Panel Handle
new Handle:g_hRules = INVALID_HANDLE;

// Timer Handle
new Handle:g_hCooldownTimer = INVALID_HANDLE;
new Handle:g_hAntiStuckTimer = INVALID_HANDLE;

// Vector
new Float:g_vSpawnPosition[3];
new Float:g_vAttackSpawnPosition[3];

// Arrays
new bool:g_aPlayerThinkHook[MAXPLAYERS + 1];
new bool:g_aPlayerGodMode[MAXPLAYERS + 1];
new g_aPlayerMoney[MAXPLAYERS + 1];

// WarStatus
new WarStatus:g_wsCurrentWarStatus = WS_WAITING;

/*
	Loading Stuff
*/

public OnPluginStart()
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
	g_cBuy = AutoExecConfig_CreateConVar("sm_war_buy", "1", "Enable buy during war (1 = Enable / 0 = Disable)", _, true, 0.0, true, 1.0);
	g_cShowRules = AutoExecConfig_CreateConVar("sm_war_show_rules", "1", "Enable rules (1 = Enable / 0 = Disable)", _, true, 0.0, true, 1.0);
	g_cWarMoney = AutoExecConfig_CreateConVar("sm_war_money", "16000", "How much money the players get during War", _, true, 0.0);
	g_cBuyTime = AutoExecConfig_CreateConVar("sm_war_buy_time", "999", "Buytime during war (CS:GO uses seconds, CS:S uses minutes here)");
	g_cLimitRounds = AutoExecConfig_CreateConVar("sm_war_limit_rounds", "10", "Min rounds between two war rounds (<= 0 = Disable limit)");
	g_cDurationRounds = AutoExecConfig_CreateConVar("sm_war_duration_rounds", "3", "How many rounds will one war take", _, true, 1.0);
	g_cAttackTeam = AutoExecConfig_CreateConVar("sm_war_attack_team", "2", "Which team will attack / wait in the equipment room? (1 = Random, 2 = Terrorists, 3 = Counter Terrorists)", _, true, 1.0, true, 3.0);
	g_cLimitTime = AutoExecConfig_CreateConVar("sm_war_limit_time", "600", "Max time a war round will take ( <= 0 = Disable limit )");
	g_cRulesTime = AutoExecConfig_CreateConVar("sm_war_rules_display_time", "10", "Time in seconds the rules should be displayed");
	g_cCooldownTime = AutoExecConfig_CreateConVar("sm_war_cooldown_time", "30.0", "Time in seconds the war starts after round start");
	g_cAntiStuckTime = AutoExecConfig_CreateConVar("sm_war_antistuck_time", "3.0", "Time in seconds antistuck will be enabled");
	g_cDFFreezeTime = FindConVar("mp_freezetime");
	g_cDFBuyTime = FindConVar("mp_buytime");

	HookConVarChange(g_cBuy, ConVarChanged);
	HookConVarChange(g_cBuyTime, ConVarChanged);
	HookConVarChange(g_cDurationRounds, ConVarChanged);
	HookConVarChange(g_cAttackTeam, ConVarChanged);
	HookConVarChange(g_cLimitTime, ConVarChanged);
	HookConVarChange(g_cLimitRounds, ConVarChanged);
	HookConVarChange(g_cRulesTime, ConVarChanged);

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

	// Offsets
	g_iPlayerAccount = FindSendPropOffs("CCSPlayer", "m_iAccount");

	if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public OnLibraryAdded(const String:name[])
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL)
    }
}

public OnMapStart()
{
	FindCTSpawnPosition();
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
   CreateNative("WAR_SetStatus", Native_Set_Status);
   CreateNative("WAR_IsWar", Native_Is_War);
   CreateNative("WAR_IsInit", Native_Is_Init);
   CreateNative("WAR_GetWarRounds", Native_Get_WarRounds);
   MarkNativeAsOptional("Updater_AddPlugin");
   return APLRes_Success;
}

public ConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[]) 
{
	if(!strcmp(oldValue, newValue))
	{
		UpdateSetting(convar);
	}
}

/*
	Events
*/

public Event_RoundStart_Callback(Handle:event, const String:name[], bool:dontBroadcast)
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
	}
}

public Event_RoundEnd_Callback(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Kill all active Timers
	SaveKillTimer(g_hAntiStuckTimer);
	SaveKillTimer(g_hCooldownTimer);
}

public Event_PlayerDisconnect_Callback(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Someone left the game
	new p_iUserid = GetEventInt(event, "userid");
	new p_iClient = GetClientOfUserId(p_iUserid);

	// Dectivate Think Hook
	if(g_aPlayerThinkHook[p_iClient])
	{
		SDKUnhook(p_iClient, SDKHook_PostThink, SDKHook_PostThink_Callback);
		g_aPlayerThinkHook[p_iClient] = false;
	}

	// Reset money
	g_aPlayerMoney[p_iClient] = 0;
}

public Event_PlayerConnect_Callback(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Someone joined the game
	new p_iUserid = GetEventInt(event, "userid");
	new p_iClient = GetClientOfUserId(p_iUserid);

	// Activate Think Hook
	if(g_bIsWar)
	{
		g_aPlayerThinkHook[p_iClient] = SDKHookEx(p_iClient, SDKHook_PostThink, SDKHook_PostThink_Callback);
	}
}

/*
	Hooks
*/

public SDKHook_PostThink_Callback(client) 
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

public PanelCallback_Rules(Handle:menu, MenuAction:action, param1, param2)
{
	// Nothing
}

/*
	Timer Callbacks
*/

public Action:Timer_DisableAntiStuck(Handle:timer, any:team)
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Stopping anti stuck after %f seconds for team: %i!", g_fAntiStuckTime, team);
	}
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team)
		{
			SetEntProp(i, Prop_Data, "m_CollisionGroup", 5);
		}
	}

	g_hAntiStuckTimer = INVALID_HANDLE;
}

public Action:Timer_Cooldown(Handle:timer)
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Attacker team is getting free now!");
		PrintToServer("[WAR] Starting anti stuck!");
	}

	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == g_iAttackTeam)
		{
			AntiStuckTeam(g_iAttackTeam, false);
			SetEntityMoveType(i, MOVETYPE_WALK);
		}
	}

	g_hAntiStuckTimer = CreateTimer(g_fAntiStuckTime, Timer_DisableAntiStuck, g_iAttackTeam);
	g_bIsCooldown = false;
	CheckGodMode(true);

	g_hCooldownTimer = INVALID_HANDLE;
}

/*
	Natives
*/

public Native_Is_War(Handle:plugin, numParams)
{
	// Simly a getter function
	return g_bIsWar;	
}

public Native_Is_Init(Handle:plugin, numParams)
{
	// Simly a getter function
	if(g_wsCurrentWarStatus == WS_INITIALISING)
	{
		return true;	
	}
	return false;
}

public Native_Get_WarRounds(Handle:plugin, numParams)
{
	return g_iWarRounds;
}

public Native_Set_Status(Handle:plugin, numParams)
{
	SetStatus(GetNativeCell(1));
	if(g_bDebug)
	{
		PrintToServer("[War] Native_Set_Status called!");
	}
}


/***************
	Private
	Functions
****************/


/*
	Settings
*/

UpdateSetting(Handle:convar = INVALID_HANDLE){
	if(g_bDebug)
	{
		PrintToServer("[WAR] A ConVar changed");
	}
	if(convar == g_cBuy)
	{
		g_bBuy = GetConVarBool(g_cBuy);
	}
	else if(convar == g_cBuyTime)
	{
		g_iBuyTime = GetConVarInt(g_cBuyTime);
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
	else if(convar == g_cLimitTime)
	{
		g_iLimitTime = GetConVarInt(g_cLimitTime);
	}
	else if(convar == g_cRulesTime)
	{
		g_iRulesTime = GetConVarInt(g_cRulesTime);
	}
	else if(convar == g_cCooldownTime)
	{
		g_fCooldownTime = GetConVarFloat(g_cCooldownTime);
	}
	else if(convar == g_cAntiStuckTime)
	{
		g_fAntiStuckTime = GetConVarFloat(g_cAntiStuckTime);
	}
}

UpdateAllSettings()
{
	if(g_cBuy != INVALID_HANDLE)
	{
		g_bBuy = GetConVarBool(g_cBuy);
	}
	if(g_cBuyTime != INVALID_HANDLE)
	{
		g_iBuyTime = GetConVarInt(g_cBuyTime);
	}
	if(g_cShowRules != INVALID_HANDLE)
	{
		g_bShowRules = GetConVarBool(g_cShowRules);
		if(g_bShowRules)
		{
			PrepareRules();
		}
	}
	if(g_cLimitRounds != INVALID_HANDLE)
	{
		g_iLimitRounds = GetConVarInt(g_cLimitRounds);
	}
	if(g_cDurationRounds != INVALID_HANDLE)
	{
		g_iDurationRounds = GetConVarInt(g_cDurationRounds);
	}
	if(g_cAttackTeam != INVALID_HANDLE)
	{
		g_iAttackTeam = GetConVarInt(g_cAttackTeam);
	}
	if(g_cLimitTime != INVALID_HANDLE)
	{
		g_iLimitTime = GetConVarInt(g_cLimitTime);
	}
	if(g_cRulesTime != INVALID_HANDLE)
	{
		g_iRulesTime = GetConVarInt(g_cRulesTime);
	}
	if(g_cCooldownTime != INVALID_HANDLE)
	{
		g_fCooldownTime = GetConVarFloat(g_cCooldownTime);
	}
	if(g_cAntiStuckTime != INVALID_HANDLE)
	{
		g_fAntiStuckTime = GetConVarFloat(g_cAntiStuckTime);
	}
}

/*
	Find Spawn for War
*/

FindCTSpawnPosition()
{
	if(g_bDebug)
	{
		PrintToServer("[WAR] Searching for spawn");
	}
	// Find CT spawn and save it's positions
	decl String:p_sClassName[64];
	for(new i = MaxClients; i < GetMaxEntities(); i++)
	{
		if(IsValidEdict(i) && IsValidEntity(i))
		{
			GetEdictClassname(i, p_sClassName, sizeof(p_sClassName));
			if(StrEqual("info_player_counterterrorist", p_sClassName))
			{
				// This is a CT Spawn. Save it's position!
				decl Float:p_vPosition[3];
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

PrepareRules()
{
	decl String:p_sPathConfig[PLATFORM_MAX_PATH], String:p_sBuffer[256];
	BuildPath(Path_SM, p_sPathConfig, sizeof(p_sPathConfig), "configs/war/rules.txt");
	if(g_bDebug)
	{

		PrintToServer("[WAR] Searching for rules file @: %s", p_sPathConfig);
	}
	if(FileExists(p_sPathConfig))
	{
		if(g_hRules != INVALID_HANDLE)
		{
			CloseHandle(g_hRules);
		}
		g_hRules = CreatePanel();
		Format(p_sBuffer, sizeof(p_sBuffer), "%T", "RulesTitle", LANG_SERVER);
		SetPanelTitle(g_hRules, p_sBuffer);

		new Handle:p_hFile = INVALID_HANDLE;
		decl String:p_sLine[256];
		p_hFile = OpenFile(p_sPathConfig, "r");
		if(g_bDebug)
		{
			PrintToServer("[WAR] Opend rules file:");
		}
		if(p_hFile != INVALID_HANDLE)
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

ShowRules()
{
	// We show the important rules!
	if(g_bDebug)
	{
		PrintToServer("[WAR] Showing the rules");
	}
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && (GetClientTeam(i) == 2 || GetClientTeam(i) == 3))
		{
			PrintToServer("[WAR] Showing the rules to: %N", i);
			SendPanelToClient(g_hRules, i, PanelCallback_Rules, g_iRulesTime);
		}
	}
}

/*
	Set the War status
*/

SetStatus(WarStatus:NewWarStatus)
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
				g_wsCurrentWarStatus = WS_INITIALISING;
				if(g_bDebug)
				{
					PrintToServer("[WAR] New Status: War gets initialised");
				}
				return true;
			}
			else if(g_iMinNoWarRounds <= 0)
			{
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
			g_wsCurrentWarStatus =  WS_WAITING;
			if(g_bDebug)
			{
				PrintToServer("[WAR] New Status: Waiting");
			}
			return true;
		}
		else if(NewWarStatus == WS_PROCESS)
		{
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
		g_wsCurrentWarStatus = NewWarStatus;
		g_iMinNoWarRounds = g_iLimitRounds;
		g_bIsWar = false;
		return true;
	}
	return false;
}

/*
	Teleport and start timers
*/

TeleportToWar()
{
	// Free transfer to equipment room :O
	if(g_bDebug)
	{

		PrintToServer("[WAR] Teleporting players now");
	}
	for(new i = 1; i <= MaxClients; i++)
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

AntiStuckTeam(any:p_iTeam, bool:p_bAddFreezetime = false)
{
	for(new i = 1; i <= MaxClients; i++)
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

ActivateHooks()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !g_aPlayerThinkHook[i])
		{
			// Now i gonna know when you think. Ha Ha !
			g_aPlayerThinkHook[i] = SDKHookEx(i, SDKHook_PostThink, SDKHook_PostThink_Callback);
		}
	}
}

DeactivateHooks()
{
	for(new i = 1; i <= MaxClients; i++)
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

CheckGodMode(bool:p_bDeactivate = false, any:p_iClient = 0, any:p_iTeam = 0)
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
			for(new i = 1; i <= MaxClients; i++)
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

		for(new i = 1; i <= MaxClients; i++)
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
		for(new i = 1; i <= MaxClients; i++)
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

	for(new i = 1; i <= MaxClients; i++)
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

SetMoney()
{
	// Some money for the world

	if(g_bIsWar)
	{
		for(new i = 1; i <= MaxClients; i++)
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
		for(new i = 1; i <= MaxClients; i++)
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
stock RemoveAllWeapons(any:client)
{
	// No Equipment ! ( K, knive is allowed ;) )
	new wepIdx;
	for (new i; i < 4; i++)
	{
		while ((wepIdx = GetPlayerWeaponSlot(client, i)) != -1)
		{
			RemovePlayerItem(client, wepIdx);
			AcceptEntityInput(wepIdx, "Kill");
		}
	}
	GivePlayerItem(client, "weapon_knive");
}


// Credits for this go to Alliedmodders ( who made this btw? )
stock SaveKillTimer(&Handle:Timer)
{
    if(Timer != INVALID_HANDLE)
    {
        CloseHandle(Timer);
        Timer = INVALID_HANDLE;
    }
}