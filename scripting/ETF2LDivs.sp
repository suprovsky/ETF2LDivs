#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <system2>
#include <morecolors>
#include <smlib>
#define VERSION 		"0.1"

ConVar g_hCvarEnabled;
ConVar g_hCvarAnnounce;
ConVar g_hCvarAnnAdminOnly;
ConVar g_hCvarTeamType;
//ConVar g_hCvarMaxAge;
ConVar g_hCvarSeasonsOnly;

bool g_bEnabled;
bool g_bAnnounce;
bool g_bSeasonsOnly;
bool g_bAnnounceAdminOnly;
char g_sTeamType[64];

//int g_iMaxAge = 604800;

Regex g_hRegExSeason;

StringMap g_hPlayerData[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "ETF2LDivs",
	author = "suprovsky",
	description = "Shows a players ETF2L team and division.",
	version = VERSION,
};

public void OnPluginStart() {
	CreateConVar("sm_etf2ldivs_version", VERSION, "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	// Create some convars
	g_hCvarEnabled = CreateConVar("sm_etf2ldivs_enable", "1", "Enable ETF2LDivs.", 0, true, 0.0, true, 1.0);
	g_hCvarTeamType = CreateConVar("sm_etf2ldivs_teamtype", "6on6", "The team type to show (6on6, Highlander, 2on2...).", 0);
	g_hCvarAnnounce = CreateConVar("sm_etf2ldivs_announce", "1", "Announce players on connect.", 0, true, 0.0, true, 1.0);
	g_hCvarSeasonsOnly = CreateConVar("sm_etf2ldivs_seasonsonly", "1", "Ignore placements in fun cups etc.", 0, true, 0.0, true, 1.0);
	g_hCvarAnnAdminOnly = CreateConVar("sm_etf2ldivs_announce_adminsonly", "0", "Announce players on connect to admins only.", 0, true, 0.0, true, 1.0);
	//g_hCvarMaxAge = CreateConVar("sm_etf2ldivs_maxage", "7", "Update infos about all players every x-th day.", 0, true, 1.0, true, 31.0);
	g_hCvarEnabled.AddChangeHook(Cvar_Changed);
	g_hCvarAnnounce.AddChangeHook(Cvar_Changed);
	g_hCvarAnnAdminOnly.AddChangeHook(Cvar_Changed);
	g_hCvarSeasonsOnly.AddChangeHook(Cvar_Changed);
	g_hCvarTeamType.AddChangeHook(Cvar_Changed);
	//g_hCvarMaxAge.AddChangeHook(Cvar_Changed);

	// Match season information by regex. Overkill, but eaaase.
	g_hRegExSeason = new Regex("Season (\\d\\d)");

	// Create the cache directory if it does not exist
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/etf2lcache/");

	if (!DirExists(path)) {
		CreateDirectory(path, 493);
	}

	// Provide a command for clients
	RegConsoleCmd("sm_div", Command_ShowDivisions);
	RegConsoleCmd("sm_divdetail", Command_ShowPlayerDetail);
}

public void OnConfigsExecuted() {
	g_bEnabled = g_hCvarEnabled.BoolValue;
	g_bAnnounce = g_hCvarAnnounce.BoolValue;
	g_bAnnounceAdminOnly = g_hCvarAnnAdminOnly.BoolValue;
	g_bSeasonsOnly = g_hCvarSeasonsOnly.BoolValue;
	g_hCvarTeamType.GetString(g_sTeamType, sizeof(g_sTeamType));
	//g_iMaxAge = g_hCvarMaxAge.IntValue * (24 * 60 * 60);

	// Account for late loading
	// - This triggers announcements. But that shouldn't be a big deal,
	//   so we don't handle it and overcomplicate things by doing so.
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsFakeClient(client)) {
			char authStr[32];
			GetClientAuthId(client, AuthId_Steam2, authStr, sizeof(authStr));
			UpdateClientData(client, authStr);
		}
	}
}

public void Cvar_Changed(ConVar convar, const char[] oldValue, const char[] newValue) {
	OnConfigsExecuted();
}

public Action Command_ShowPlayerDetail(int client, int args) {
	if (!g_bEnabled) {
		ReplyToCommand(client, "tDivisions is disabled.");
		return Plugin_Handled;
	}

	if (args == 0 || args > 1) {
		ReplyToCommand(client, "No target specified. Usage: sm_divdetail <playername>");
		//TODO: make better argument parsing
		return Plugin_Handled;
	}

	char target[32];
	GetCmdArg(1, target, sizeof(target));

	// Process the targets
	char targetName[MAX_TARGET_LENGTH];
	int targetList[MAXPLAYERS];
	bool targetTranslate;
	int targetCount = ProcessTargetString(
		target,
		client,
		targetList,
		MAXPLAYERS,
		COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_MULTI,
		targetName,
		sizeof(targetName),
		targetTranslate
	);

	if (targetCount <= 0) {
		return Plugin_Handled;
	}
	char playerID[12];
	// Apply to all targets (this can only be one, but anyway...)
	for (int i = 0; i < targetCount; i++) {
		g_hPlayerData[targetList[i]].GetString("PlayerId", playerID, sizeof(playerID));
		
		if (strlen(playerID) <= 0) {
			ReplyToCommand(client, "Sorry. The ETF2L user-id is unknown for '%s'", target);
			return Plugin_Handled;
		}

		char url[128];
		Format(url, sizeof(url), "https://etf2l.org/forum/user/%s/", playerID);

		ShowMOTDPanel(client, "ETF2L Profile", url, MOTDPANEL_TYPE_URL);
	}

	return Plugin_Handled;
}

public Action Command_ShowDivisions(int client, int args) {
	if (!g_bEnabled) {
		ReplyToCommand(client, "tDivisions is disabled.");
		return Plugin_Handled;
	}
	if (args == 0) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && g_hPlayerData[i] != null) {
				char msg[253];
				GetAnnounceString(i, msg, sizeof(msg));

				Color_ChatSetSubject(i);
				Client_PrintToChat(client, false, msg);
				PrintToServer("Whole message (Command_ShowDivisions): %s", msg);
			}
		}
	}
	
	if (args == 1) {
		char targetStr[32];
		GetCmdArg(1, targetStr, sizeof(targetStr));

		// Process the targets
		char targetName[MAX_TARGET_LENGTH];
		int targetList[MAXPLAYERS];
		bool targetTranslate;
		int targetCount = ProcessTargetString(
			targetStr,
			client,
			targetList,
			MAXPLAYERS,
			COMMAND_FILTER_CONNECTED,
			targetName,
			sizeof(targetName),
			targetTranslate
		);

		if (targetCount <= 0) {
			return Plugin_Handled;
		}

		// Apply to all targets
		for (int i = 0; i < targetCount; i++) {
			int target = targetList[i];
			if (IsClientInGame(target) && !IsFakeClient(target) && g_hPlayerData[target] != null) {
				char msg[253];
				GetAnnounceString(target, msg, sizeof(msg));

				Color_ChatSetSubject(target);
				Client_PrintToChat(client, false, msg);
				PrintToServer("Whole message (Command_ShowDivisions(ALL)): %s", msg);
			}
		}
	}

	return Plugin_Handled;
}


public void OnClientAuthorized(int client, const char[] auth) {
	if (g_bEnabled) {
		UpdateClientData(client, auth);
	}
}

public void OnClientDisconnect(int client) {
	delete g_hPlayerData[client];
}

char g_path[PLATFORM_MAX_PATH];
int g_client;
public void UpdateClientData(int client, const char[] auth) {
	if (IsFakeClient(client)) {
		return;
	}

	char friendID[64];
	AuthIDToFriendID(auth, friendID, sizeof(friendID));

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/etf2lcache/%s.vdf", friendID);
	g_path = path;
	g_client = client;
	char sWebPath[255];
	Format(sWebPath, sizeof(sWebPath), "https://api.etf2l.org/player/%s/full.vdf", auth);
	PrintToServer("Requested URL: %s", sWebPath);
	System2HTTPRequest httpRequest = new System2HTTPRequest(httpResponseCallback, sWebPath);
	httpRequest.FollowRedirects = true;
	//example: 76561198011558250.vdf
	httpRequest.SetOutputFile(path);
	httpRequest.SetVerifySSL(false);
	httpRequest.Timeout = 30;
	httpRequest.GET();
	delete httpRequest;
}

public void AnnounceWhenDataDownloaded(int client, const char[] path)
{
	delete g_hPlayerData[client];
	g_hPlayerData[client] = ReadPlayer(client, path);

	if (g_bAnnounce && g_hPlayerData[client] != null) {
		AnnouncePlayerToAll(client);
	}
}


public void httpResponseCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    if (success) {
        char lastURL[128];
        response.GetLastURL(lastURL, sizeof(lastURL));

        int statusCode = response.StatusCode;
        float totalTime = response.TotalTime;
		AnnounceWhenDataDownloaded(g_client, g_path);
        PrintToServer("Request to %s finished with status code %d in %.2f seconds", lastURL, statusCode, totalTime);
    } else {
        PrintToServer("Error on request: %s", error);
    }
} 





public void GetAnnounceString(int client, char[] msg, int maxlen) {

	Format(msg, maxlen, "{T}%N{N}", client);

	if (g_hPlayerData[client] != null) {
		char steamID[32];
		char displayName[255];
		char teamName[255];
		char divisionName[32];
		char eventName[255];

		g_hPlayerData[client].GetString("SteamId", steamID, sizeof(steamID));
		g_hPlayerData[client].GetString("DisplayName", displayName, sizeof(displayName));

		char resultKey[255];
		FormatEx(resultKey, sizeof(resultKey), "team_%s", g_sTeamType);

		StringMap teamData = null;
		if (g_hPlayerData[client].GetValue(resultKey, teamData) && teamData != null) {
			teamData.GetString("TeamName", teamName, sizeof(teamName));
			teamData.GetString("Division", divisionName, sizeof(divisionName));
			teamData.GetString("Event", eventName, sizeof(eventName));
		}
		//TODO: add user title (like League Admin etc)
		//Player is registered
		Format(msg, maxlen, "%s {N}(%s){N}", msg, displayName);

		if (strlen(teamName) > 0) {
			//Player has a team
			Format(msg, maxlen, "%s, {OG}%s{N}", msg, teamName);

			if (strlen(divisionName) > 0) {
				Format(msg, maxlen, "%s, {OG}%s{N}, %s", msg, eventName, divisionName);
			}
			else {
				StrCat(msg, maxlen, ", inactive");
			}

		}
		else {
			StrCat(msg, maxlen, ", no team");
		}
	}
	else {
		StrCat(msg, maxlen, ", unregistered");
	}

	return;
}

public void AnnouncePlayerToAll(int client) {
	PrintToServer("I'm starting announcing info for client %d", client);
	char msg[253];
	GetAnnounceString(client, msg, sizeof(msg));

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			if (g_bAnnounceAdminOnly && GetUserAdmin(i) == INVALID_ADMIN_ID) {
				continue;
			}

			Color_ChatSetSubject(client);
			Client_PrintToChat(i, false, msg);
			PrintToServer("Whole message (AnnouncePlayerToAll): %s", msg);
		}
	}
}

public StringMap ReadPlayer(int client, const char[] path) {
	PrintToServer("I'm starting reading data for client %d, path %s", client, path);
	KeyValues kv = new KeyValues("response");
	kv.ImportFromFile(path);

	if (kv == null) {
		LogError("Could not parse keyvalues file '%s' for %N", path, client);
		PrintToServer("Could not parse keyvalues file '%s' for %N, kv == null", path, client);
		return null;
	}

	if (!kv.JumpToKey("player")) {
		LogError("No player entry found for %N (%s)", client, path);
		PrintToServer("Could not parse keyvalues file '%s' for %N, JumpToKey", path, client);
		delete kv;
		return null;
	}

	int etf2lID = kv.GetNum("id", -1);
	PrintToServer("ETF2L ID: %d", etf2lID);
	if (etf2lID == -1) {
		delete kv;
		return null;
	}

	// Start collecting data and save it in a trie
	StringMap hResult = new StringMap();
	char etf2lIDString[8];
	IntToString(etf2lID, etf2lIDString, sizeof(etf2lIDString)-1);
	hResult.SetString("PlayerId", etf2lIDString);

	// Grab Player Details
	char displayName[255];
	kv.GetString("name", displayName, sizeof(displayName), "");
	hResult.SetString("DisplayName", displayName);

	char steamID[32];
	if (kv.JumpToKey("steam")) {
		kv.GetString("id", steamID, sizeof(steamID), "");
		kv.GoBack();
	}
	hResult.SetString("SteamId", steamID);

	char title[32];
	if (kv.JumpToKey("player")) {
		kv.GetString("title", title, sizeof(title), "");
		kv.GoBack();
	}
	hResult.SetString("title", title);

	// Loop over all teams
	if (kv.JumpToKey("teams")) {
		if (kv.GotoFirstSubKey(false)) {
			do {
				char teamType[32];
				kv.GetString("type", teamType, sizeof(teamType), "");

				char teamName[255];
				kv.GetString("name", teamName, sizeof(teamName), "");

				char eventName[255];
				char divisionName[255];
				if (kv.JumpToKey("competitions")) {
					// Find the competition with the highest Id
					if (kv.GotoFirstSubKey(false)) {
						int iHighestCompetitionId = -1;
						do {
							char sCompetitionId[8];
							kv.GetSectionName(sCompetitionId, sizeof(sCompetitionId));

							// Filter by category if only season should be shown
							char sCategory[64];
							kv.GetString("category", sCategory, sizeof(sCategory), "");
							if (g_bSeasonsOnly && StrContains(sCategory, "Season", false) == -1) {
								continue;
							}

							int iCompetitionId = StringToInt(sCompetitionId);
							if (iCompetitionId > iHighestCompetitionId) {
								iHighestCompetitionId = iCompetitionId;

								kv.GetString("competition", eventName, sizeof(eventName));

								if (kv.JumpToKey("division")) {
									kv.GetString("name", divisionName, sizeof(divisionName));

									kv.GoBack();
								}
							}
						} while (kv.GotoNextKey(false));

						kv.GoBack();
					}

					kv.GoBack();
				}

				// Post-Processing: Strip the event name
				if (g_hRegExSeason.Match(eventName) > 0) {
					char sYear[4];
					g_hRegExSeason.GetSubString(1, sYear, sizeof(sYear));

					Format(eventName, sizeof(eventName), "Season %s", sYear);
				}

				// Store in trie and append to result trie
				StringMap teamData = new StringMap();
				teamData.SetString("TeamName", teamName);
				teamData.SetString("Division", divisionName);
				teamData.SetString("Event", eventName);

				char resultKey[255];
				Format(resultKey, sizeof(resultKey), "team_%s", teamType);

				hResult.SetValue(resultKey, teamData);

			} while (kv.GotoNextKey(false));

			kv.GoBack();
		}

		kv.GoBack();
	}

	delete kv;

	return hResult;
}

void AuthIDToFriendID(const char[] auth, char[] friendIDStr, int size) {
	char authStr[32];
	strcopy(authStr, sizeof(authStr), auth);

	ReplaceString(authStr, strlen(authStr), "STEAM_", "");

	if (StrEqual(authStr, "ID_LAN")) {
		friendIDStr[0] = '\0';

		return;
	}

	char toks[3][16];

	ExplodeString(authStr, ":", toks, sizeof(toks), sizeof(toks[]));

	//new unknown = StringToInt(toks[0]);
	int server = StringToInt(toks[1]);
	int authID = StringToInt(toks[2]);

	int friendID = (authID*2) + 60265728 + server;

	Format(friendIDStr, size, "765611979%d", friendID);
}


// 	// If the file already exists and is young enough, reply instantly
// 	if(iMaxAge != 0 && FileExists(sPath)) {
// 		new iFileTime = GetFileTime(sPath, FileTime_LastChange);
// 		new iNow = GetTime();

// 		if(iNow - iFileTime < iMaxAge) {
// 			Call_StartFunction(hPlugin, funcCallback);
// 			Call_PushCell(true);
// 			Call_PushCell(hSocketData);
// 			Call_PushCell(data);
// 			Call_Finish();

// 			CloseHandle(hSocketData);
// 			return true;
// 		}
// 	}