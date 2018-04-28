/*
	Add auto-ban after X # TKs on record? Per map or total? Add cvar for both + ban lengths. Set count # to 0 to disable. Length of 0 = perm.
*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <autoexecconfig> //https://github.com/Impact123/AutoExecConfig or http://www.togcoding.com/showthread.php?p=1862459
#include <geoip>
#include <togtktracker>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.3"

Handle g_hDatabaseName = null;
char g_sDatabaseName[32];
Handle g_hNotifyCnt = null;
int g_iNotifyCnt;
Handle g_hAdminFlag = null;
char g_sAdminFlag[30];

char ga_sSteamID[MAXPLAYERS + 1][32];
char ga_sName[MAXPLAYERS + 1][32];
bool ga_bLoaded[MAXPLAYERS + 1] = {false, ...};
int ga_iTKs[MAXPLAYERS + 1] = {0, ...};
int ga_iTKsFromDB[MAXPLAYERS + 1] = {0, ...};

//misc server variables
Handle g_hClientLoadFwd = null;
Handle g_hTKEventFwd = null;
Handle g_hDatabase = null;
bool g_bDBLoaded = false;
bool g_bLateLoad;
char g_sMapName[64] = "";
char g_sServerIP[64] = "";

public Plugin myinfo =
{
	name = "TOG TK Tracker",
	author = "That One Guy",
	description = "Tracker team kills and provides natives and forwards to interact with other plugins",
	version = PLUGIN_VERSION,
	url = "http://www.togcoding.com"
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max)
{
	CreateNative("ttkt_GetTKCnt_Map", Native_GetTKCnt_Map);
	CreateNative("ttkt_GetTKCnt_Total", Native_GetTKCnt_Total);
	
	RegPluginLibrary("togtktracker");
	
	g_bLateLoad = bLate;
	return APLRes_Success;
}

public void OnPluginStart()
{
	AutoExecConfig_SetFile("togtktracker");
	AutoExecConfig_CreateConVar("ttkt_version", PLUGIN_VERSION, "TOG Insurgency Stats: Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_hDatabaseName = AutoExecConfig_CreateConVar("ttkt_dbname", "togtktracker", "Name of the main database setup for the plugin.");
	HookConVarChange(g_hDatabaseName, OnCVarChange);
	GetConVarString(g_hDatabaseName, g_sDatabaseName, sizeof(g_sDatabaseName));
	
	g_hNotifyCnt = AutoExecConfig_CreateConVar("ttkt_notifycnt", "5", "Admins are notified if a connecting player has at least this number of TKs on record. Set to 0 to disable notification.", _, true, 0.0);
	HookConVarChange(g_hNotifyCnt, OnCVarChange);
	g_iNotifyCnt = GetConVarInt(g_hNotifyCnt);
	
	g_hAdminFlag = AutoExecConfig_CreateConVar("ttkt_adminflag", "b", "Players with this flag will be notified when a connecting player has a TK count above ttkt_notifycnt.", _);
	HookConVarChange(g_hAdminFlag, OnCVarChange);
	GetConVarString(g_hAdminFlag, g_sAdminFlag, sizeof(g_sAdminFlag));
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));
	GetServerIP();
	
	SetDBHandle();
	
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_changename", Event_NameChange);
	
	g_hClientLoadFwd = CreateGlobalForward("ttkt_ClientLoaded", ET_Event, Param_Cell);
	g_hTKEventFwd = CreateGlobalForward("ttkt_TKEvent", ET_Event, Param_Cell);
}

public void OnCVarChange(Handle hCVar, const char[] sOldValue, const char[] sNewValue)
{
	if(hCVar == g_hDatabaseName)
	{
		GetConVarString(g_hDatabaseName, g_sDatabaseName, sizeof(g_sDatabaseName));
	}
	else if(hCVar == g_hNotifyCnt)
	{
		g_iNotifyCnt = StringToInt(sNewValue);
	}
	else if(hCVar == g_hAdminFlag)
	{
		GetConVarString(g_hAdminFlag, g_sAdminFlag, sizeof(g_sAdminFlag));
	}
}

public void OnAutoConfigsBuffered()
{
	SetDBHandle();
}

public void OnConfigsExecuted()
{
	if(g_hDatabase == null)
	{
		SetDBHandle();
	}
	
	if(g_bLateLoad)
	{
		char sQuery[250];
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
				GetClientAuthId(i, AuthId_Steam2, ga_sSteamID[i], sizeof(ga_sSteamID[]));
#else
				GetClientAuthString(i, ga_sSteamID[i], sizeof(ga_sSteamID[]));
#endif
				ReplaceString(ga_sSteamID[i], sizeof(ga_sSteamID[]), "STEAM_1", "STEAM_0", true);	//so that this works across multiple games, convert steam IDs to steam universe 1
				if(StrContains(ga_sSteamID[i], "STEAM_", true) == -1) //if ID is invalid
				{
					CreateTimer(10.0, RefreshSteamID, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
				}
				else
				{
					if(g_hDatabase == null)
					{
						CreateTimer(2.0, RepeatCheck, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
					}
					else
					{
						Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM togtktracker WHERE (steamid = '%s')", ga_sSteamID[i]);
						SQL_TQuery(g_hDatabase, SQLCallback_LoadPlayer, sQuery, GetClientUserId(i));
					}
				}
			}
		}
	}
}

void GetServerIP()
{
	int aArray[4];
	int iLongIP = GetConVarInt(FindConVar("hostip"));
	aArray[0] = (iLongIP >> 24) & 0x000000FF;
	aArray[1] = (iLongIP >> 16) & 0x000000FF;
	aArray[2] = (iLongIP >> 8) & 0x000000FF;
	aArray[3] = iLongIP & 0x000000FF;
	Format(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d_%i", aArray[0], aArray[1], aArray[2], aArray[3], GetConVarInt(FindConVar("hostport")));
}

public void OnMapStart()
{
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));
}

public Action RefreshSteamID(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client))
	{
		return;
	}

#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
	GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
#else
	GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
#endif
	ReplaceString(ga_sSteamID[client], sizeof(ga_sSteamID[]), "STEAM_1", "STEAM_0", true);	//so that this works across multiple games, convert steam IDs to steam universe 1
	if(StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //still invalid - retry again
	{
		CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		char sQuery[250];
		Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM togtktracker WHERE (steamid = '%s')", ga_sSteamID[client]);
		SQL_TQuery(g_hDatabase, SQLCallback_LoadPlayer, sQuery, GetClientUserId(client));
	}
}

void SetDBHandle()
{
	if(g_hDatabase == null)
	{
		SQL_TConnect(SQLCallback_Connect, g_sDatabaseName);
	}
}

public void SQLCallback_Connect(Handle hOwner, Handle hHndl, const char[] sError, any data)
{
	if(hHndl == null)
	{
		SetFailState("Error connecting to database. %s", sError);
	}
	else
	{
		g_hDatabase = hHndl;
		char sDriver[64], sQuery[600];
		
		SQL_ReadDriver(g_hDatabase, sDriver, 64);
		if(StrEqual(sDriver, "sqlite"))
		{
			Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `togtktracker` (`id` int(20) PRIMARY KEY, `event_date` varchar(64) NOT NULL, `map` varchar(32) NOT NULL, `server` varchar(32) NOT NULL, `steamid` varchar(32) NOT NULL, `lastnameused` varchar(65) NOT NULL, `lastclientip` varchar(32) NOT NULL,`is_admin` INT(2) NOT NULL, `victim_id` varchar(32), `victim_name` varchar(65), `victim_ip` varchar(32))");
		}
		else
		{
			Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `togtktracker` ( `id` int(20) NOT NULL AUTO_INCREMENT, `event_date` varchar(64) NOT NULL, `map` varchar(32) NOT NULL, `server` varchar(32) NOT NULL, `steamid` varchar(32) NOT NULL, `lastnameused` varchar(65) NOT NULL, `lastclientip` varchar(32) NOT NULL,`is_admin` INT(2) NOT NULL, `victim_id` varchar(32), `victim_name` varchar(65), `victim_ip` varchar(32), PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8 AUTO_INCREMENT=1");
		}

		SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery, 1);
	}
}

public void SQLCallback_Void(Handle hOwner, Handle hHndl, const char[] sError, any iValue)
{
	if(hHndl == null)
	{
		SetFailState("Error (%i): %s", iValue, sError);
	}
	
	if(iValue == 1)
	{
		g_bDBLoaded = true;
	}
}

public void OnClientConnected(int client)
{
	ga_bLoaded[client] = false;
	ga_sSteamID[client] = "";
	GetClientName(client, ga_sName[client], sizeof(ga_sName[]));
	ga_iTKs[client] = 0;
	ga_iTKsFromDB[client] = 0;
}

public void OnClientPostAdminCheck(int client)
{
	if(IsFakeClient(client))
	{
		ga_bLoaded[client] = true;
		Format(ga_sSteamID[client], sizeof(ga_sSteamID[]), "BOT");
		return;
	}
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
	GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
#else
	GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
#endif
	if(StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //still invalid - retry again
	{
		CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else if(g_hDatabase == null)
	{
		CreateTimer(2.0, RepeatCheck, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		ReplaceString(ga_sSteamID[client], sizeof(ga_sSteamID[]), "STEAM_1", "STEAM_0", true);	//so that this works across multiple games, convert steam IDs to steam universe 1
		char sQuery[250];
		Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM togtktracker WHERE (steamid = '%s')", ga_sSteamID[client]);
		SQL_TQuery(g_hDatabase, SQLCallback_LoadPlayer, sQuery, GetClientUserId(client));
	}
}

public void SQLCallback_LoadPlayer(Handle hOwner, Handle hHndl, const char[] sError, any iUserID)
{
	if(hHndl == null)
	{
		SetFailState("Player load callback error: %s", sError);
	}
	
	int client = GetClientOfUserId(iUserID);
	if(!IsValidClient(client))
	{
		return;
	}
	else 
	{
		if(SQL_GetRowCount(hHndl) == 1)
		{
			SQL_FetchRow(hHndl);
			ga_iTKsFromDB[client] = SQL_FetchInt(hHndl, 0);
			if(g_iNotifyCnt)
			{
				if(ga_iTKsFromDB[client] + ga_iTKs[client] > g_iNotifyCnt)
				{
					MsgAdmins_Chat(g_sAdminFlag, "");
				}
			}
			ga_bLoaded[client] = true;
			Call_StartForward(g_hClientLoadFwd);
			Call_PushCell(client);
			Call_Finish();
		}
		else if(g_hDatabase == null)
		{
			CreateTimer(2.0, RepeatCheck, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
		else	//new player
		{
			ga_bLoaded[client] = true;
			Call_StartForward(g_hClientLoadFwd);
			Call_PushCell(client);
			Call_Finish();
		}
	}
}

void MsgAdmins_Chat(char[] sFlags, char[] sMsg, any ...)
{
	char sFormattedMsg[500];
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			if(HasFlags(i, sFlags))
			{
				PrintToChat(i, "%s", sFormattedMsg);
			}
		}
	}
}

public Action RepeatCheck(Handle hTimer, any iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if(IsValidClient(client))
	{
		char sQuery[250];
		Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) FROM togtktracker WHERE (steamid = '%s')", ga_sSteamID[client]);
		SQL_TQuery(g_hDatabase, SQLCallback_LoadPlayer, sQuery, GetClientUserId(client));
	}
}

public void OnClientDisconnect(int client)
{
	ga_bLoaded[client] = false;
	ga_sSteamID[client] = "";
	ga_sName[client] = "";
	ga_iTKsFromDB[client] = 0;
	ga_iTKs[client] = 0;
}

public Action Event_NameChange(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if(!client || !IsValidClient(client))
	{
		return Plugin_Continue;
	}
	GetClientName(client, ga_sName[client], sizeof(ga_sName[]));
	
	return Plugin_Continue;
}

public void Event_PlayerDeath(Handle hEvent,const char[] sName,bool bDontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	int client = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
	
	if(client == victim)
	{
		return;
	}
	
	if(IsValidClient(victim, true) && IsValidClient(client))	//only log if killer is not a bot
	{
		if(GetClientTeam(client) == GetClientTeam(victim))
		{
			LogTK(client, victim);
		}
	}
}

void LogTK(int client, int victim)
{
	ga_iTKs[client]++;
	Call_StartForward(g_hTKEventFwd);
	Call_PushCell(client);
	Call_Finish();
	if(g_bDBLoaded && (g_hDatabase != null))
	{
		bool bAdmin = false;
		if(HasFlags(client, g_sAdminFlag))
		{
			bAdmin = true;
		}
		char sQuery[500], sIP[MAX_NAME_LENGTH], sVictimIP[MAX_NAME_LENGTH], sName[MAX_NAME_LENGTH], sVictimName[MAX_NAME_LENGTH], sDate[64];
		GetClientIP(client, sIP, sizeof(sIP));
		GetClientIP(victim, sVictimIP, sizeof(sVictimIP));
		GetCleanName(client, sName, sizeof(sName));
		GetCleanName(victim, sVictimName, sizeof(sVictimName));
		FormatTime(sDate, sizeof(sDate), "%c");
		Format(sQuery, sizeof(sQuery), "INSERT INTO togtktracker (event_date, map, server, steamid, lastnameused, lastclientip, is_admin, victim_id, victim_name, victim_ip) VALUES('%s', '%s', '%s', '%s', '%s', '%s', %i, '%s', '%s', '%s')", sDate, g_sMapName, g_sServerIP, ga_sSteamID[client], sName, sIP, bAdmin, ga_sSteamID[victim], sVictimName, sVictimIP);
		SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery, 2);
	}
	else
	{
		LogError("Player %L TK'd victim %L before the TK database could load! Map: %s.", client, victim, g_sMapName);
	}
}

void GetCleanName(int client, char[] sName, int iSize)
{
	char sBuffer[MAX_NAME_LENGTH];
	//GetClientName(client, sBuffer, sizeof(sBuffer));
	strcopy(sBuffer, iSize, ga_sName[client]);
	ReplaceString(sBuffer, iSize, "}", "");
	ReplaceString(sBuffer, iSize, "{", "");
	ReplaceString(sBuffer, iSize, "|", "");
	ReplaceString(sBuffer, iSize, "'", "");
	ReplaceString(sBuffer, iSize, "\"", "");
	ReplaceString(sBuffer, iSize, "`", "");
	ReplaceString(sBuffer, iSize, "(", "");
	ReplaceString(sBuffer, iSize, ")", "");
	strcopy(sName, iSize, sBuffer);
	//SQL_EscapeString(g_hSQLDatabase, sBuffer, sName, iSize);
}

public int Native_GetTKCnt_Map(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		return ga_iTKs[client];
	}
	
	return -1;
}

public int Native_GetTKCnt_Total(Handle hPlugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if(IsValidClient(client))
	{
		if(g_bDBLoaded)
		{
			if(ga_bLoaded[client])
			{
				return ga_iTKs[client] + ga_iTKsFromDB[client];
			}
			return -2;
		}
		return -3;
	}
	
	return -1;
}

bool IsValidClient(int client, bool bAllowBots = false)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client))
	{
		return false;
	}
	return true;
}

bool HasFlags(int client, char[] sFlags)
{
	if(StrEqual(sFlags, "public", false) || StrEqual(sFlags, "", false))
	{
		return true;
	}
	else if(StrEqual(sFlags, "none", false))	//useful for some plugins
	{
		return false;
	}
	else if(!client)	//if rcon
	{
		return true;
	}
	else if(CheckCommandAccess(client, "sm_not_a_command", ADMFLAG_ROOT, true))
	{
		return true;
	}
	
	AdminId id = GetUserAdmin(client);
	if(id == INVALID_ADMIN_ID)
	{
		return false;
	}
	int flags, clientflags;
	clientflags = GetUserFlagBits(client);
	
	if(StrContains(sFlags, ";", false) != -1) //check if multiple strings
	{
		int i = 0, iStrCount = 0;
		while(sFlags[i] != '\0')
		{
			if(sFlags[i++] == ';')
			{
				iStrCount++;
			}
		}
		iStrCount++; //add one more for stuff after last comma
		
		char[][] a_sTempArray = new char[iStrCount][30];
		ExplodeString(sFlags, ";", a_sTempArray, iStrCount, 30);
		bool bMatching = true;
		
		for(i = 0; i < iStrCount; i++)
		{
			bMatching = true;
			flags = ReadFlagString(a_sTempArray[i]);
			for(int j = 0; j <= 20; j++)
			{
				if(bMatching)	//if still matching, continue loop
				{
					if(flags & (1<<j))
					{
						if(!(clientflags & (1<<j)))
						{
							bMatching = false;
						}
					}
				}
			}
			if(bMatching)
			{
				return true;
			}
		}
		return false;
	}
	else
	{
		flags = ReadFlagString(sFlags);
		for(int i = 0; i <= 20; i++)
		{
			if(flags & (1<<i))
			{
				if(!(clientflags & (1<<i)))
				{
					return false;
				}
			}
		}
		return true;
	}
}

stock void Log(char[] sPath, const char[] sMsg, any ...)	//TOG logging function - path is relative to logs folder.
{
	char sLogFilePath[PLATFORM_MAX_PATH], sFormattedMsg[500];
	BuildPath(Path_SM, sLogFilePath, sizeof(sLogFilePath), "logs/%s", sPath);
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
	LogToFileEx(sLogFilePath, sFormattedMsg);
}

/*
CHANGELOG:
	1.0.0:
		* Initial creation.
	1.0.1:
		* Fixed a sql query having more formatting parameters than was being called (due to removing some).
		* Added filter to remove suicides.
	1.0.2:
		* Cached names in global array.
	1.0.3
		* Changed default MySQL charset from latin1 to utf8.
*/
