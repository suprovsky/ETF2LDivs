#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <system2>
#include <regex>
#define VERSION 		"0.1.1"

ConVar g_hCvarEnabled;
ConVar g_hCvarAnnounce;
ConVar g_hCvarAnnAdminOnly;
ConVar g_hCvarTeamType;
ConVar g_hCvarSeasonsOnly;

bool g_bEnabled;
bool g_bAnnounce;
bool g_bSeasonsOnly;
bool g_bAnnounceAdminOnly;
char g_sTeamType[64];

Regex g_hRegExSeason;

StringMap g_hPlayerData[MAXPLAYERS+1];

static const char ACCEPTABLE_VALUES[][] = {
    "Highlander",
    "6on6",
    "2on2",
    "1on1",
};

public Plugin myinfo = {
	name = "ETF2LDivs",
	author = "suprovsky",
	description = "Shows a players ETF2L team and division.",
	version = VERSION,
};

public void OnPluginStart() {
	CreateConVar("sm_etf2ldivs_version", VERSION, "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hCvarEnabled = CreateConVar("sm_etf2ldivs_enable", "1", "Enable ETF2LDivs.", 0, true, 0.0, true, 1.0);
	g_hCvarTeamType = CreateConVar("sm_etf2ldivs_teamtype", "6on6", "The team type to show (6on6, Highlander, 2on2...).", 0);
	g_hCvarAnnounce = CreateConVar("sm_etf2ldivs_announce", "1", "Announce players on connect.", 0, true, 0.0, true, 1.0);
	g_hCvarSeasonsOnly = CreateConVar("sm_etf2ldivs_seasonsonly", "1", "Ignore placements in fun cups etc.", 0, true, 0.0, true, 1.0);
	g_hCvarAnnAdminOnly = CreateConVar("sm_etf2ldivs_announce_adminsonly", "0", "Announce players on connect to admins only.", 0, true, 0.0, true, 1.0);
	g_hCvarEnabled.AddChangeHook(Cvar_Changed);
	g_hCvarAnnounce.AddChangeHook(Cvar_Changed);
	g_hCvarAnnAdminOnly.AddChangeHook(Cvar_Changed);
	g_hCvarSeasonsOnly.AddChangeHook(Cvar_Changed);
	g_hCvarTeamType.AddChangeHook(CvarTeamTypeChanged);

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

public void LateLoadClients(){
	// Account for late loading
	// - This triggers announcements. But that shouldn't be a big deal,
	//   so we don't handle it and overcomplicate things by doing so.
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsFakeClient(client)) {
			char authStr[32];
			GetClientAuthId(client, AuthId_SteamID64, authStr, sizeof(authStr));
			PrintToServer("Client ID: %d, AuthStr: %s", client, authStr);
			UpdateClientData(client, authStr);
		}
	}
}
public void OnConfigsExecuted() {
	g_bEnabled = g_hCvarEnabled.BoolValue;
	g_bAnnounce = g_hCvarAnnounce.BoolValue;
	g_bAnnounceAdminOnly = g_hCvarAnnAdminOnly.BoolValue;
	g_bSeasonsOnly = g_hCvarSeasonsOnly.BoolValue;
	g_hCvarTeamType.GetString(g_sTeamType, sizeof(g_sTeamType));
	//g_iMaxAge = g_hCvarMaxAge.IntValue * (24 * 60 * 60);
	LateLoadClients();
}

public void Cvar_Changed(ConVar convar, const char[] oldValue, const char[] newValue) {
    OnConfigsExecuted();
}

public void CvarTeamTypeChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    char stringName[32];
    char stringValue[32];
    convar.GetString(stringName, sizeof(stringName));
    convar.GetString(stringValue, sizeof(stringValue));
    PrintToServer("Convar changed: %s, value: %s", stringName, stringValue);
    bool found;
    for (int i = 0; i < sizeof ACCEPTABLE_VALUES; ++i) {
        if (StrEqual(ACCEPTABLE_VALUES[i], newValue)) {
            found = true;
            LateLoadClients();
            break;
        }
    }
    if (!found) {
        convar.SetString(oldValue);
        PrintToServer("Invalid convar value (%s)", newValue);
    }
}

public Action Command_ShowPlayerDetail(int client, int args) {
	//TODO: make better argument parsing
	if (!g_bEnabled) {
		ReplyToCommand(client, "tDivisions is disabled.");
		return Plugin_Handled;
	}

	if (args == 0 || args > 1) {
		ReplyToCommand(client, "No target specified. Usage: sm_divdetail <playername>");
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
		ReplyToCommand(client, "ETF2LDivs is disabled.");
		return Plugin_Handled;
	}
	if (args == 0) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && g_hPlayerData[i] != null) {
				char msg[253];
				GetAnnounceString(i, msg, sizeof(msg));
				PrintToChat(client, msg);
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
				PrintToChat(client, msg);
			}
		}
	}

	return Plugin_Handled;
}


public Action OnClientSayCommand(int client, const char[] command, const char[] args)
{    
    if (StrContains(args, "div?", false) != -1) {
        RequestFrame(frameRequestPrintDivReply, GetClientUserId(client));
    }
    return Plugin_Continue;
}

public void frameRequestPrintDivReply(int userid) {
    int client = GetClientOfUserId(userid);
    if (client) {
        char msg[72];
        GetAnnounceString(client, msg, sizeof(msg));
        PrintToChatAll(msg);
    }
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

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/etf2lcache/%s.vdf", auth);
	g_path = path;
	g_client = client;
	char sWebPath[255];
	Format(sWebPath, sizeof(sWebPath), "https://api.etf2l.org/player/%s/full.vdf", auth);
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
	PrintToServer("AnnounceWhenDataDownloaded() Client ID: %d, path %s", client, path);
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
        LogMessage("ETF2LDivs: Request to %s finished with status code %d in %.2f seconds", lastURL, statusCode, totalTime);
    } else {
        LogMessage("ETF2LDivs: Error on request: %s", error);
    }
} 

public void GetAnnounceString(int client, char[] msg, int maxlen) {

	Format(msg, maxlen, "\x03%N\x01", client);

	if (g_hPlayerData[client] != null) {
		char steamID[32];
		char displayName[255];
		char title[32];
		char teamName[255];
		char divisionName[32];
		char eventName[255];

		g_hPlayerData[client].GetString("SteamId", steamID, sizeof(steamID));
		g_hPlayerData[client].GetString("DisplayName", displayName, sizeof(displayName));
		g_hPlayerData[client].GetString("title", title, sizeof(title));
		
		char resultKey[255];
		FormatEx(resultKey, sizeof(resultKey), "team_%s", g_sTeamType);

		StringMap teamData = null;
		if (g_hPlayerData[client].GetValue(resultKey, teamData) && teamData != null) {
			teamData.GetString("TeamName", teamName, sizeof(teamName));
			teamData.GetString("Division", divisionName, sizeof(divisionName));
			teamData.GetString("Event", eventName, sizeof(eventName));
		}
		//Player is registered
		Format(msg, maxlen, "%s \x01(%s)\x01", msg, displayName);

		if (strlen(teamName) > 0) {
			//Player has a team
			Format(msg, maxlen, "%s, \x05%s\x01", msg, teamName);

			if (strlen(divisionName) > 0) {
				Format(msg, maxlen, "%s, \x05%s\x01, %s", msg, eventName, divisionName);
			}
			else {
				StrCat(msg, maxlen, ", inactive");
			}

		}
		else {
			StrCat(msg, maxlen, ", no team");
		}
		if(strlen(title) > 0 && !StrEqual(title, "Player")) {
			if (StrEqual(title, "Anti Cheat Staff") || StrEqual(title, "Senior Anti-Cheat Admin"))
			{
				Format(msg, maxlen, "%s, \x07E74C3C%s\x01", msg, title);
			}
			else if (StrEqual(title, "Trial League Admin") || StrEqual(title, "League Admin"))
			{
				Format(msg, maxlen, "%s, \x072ECC71%s\x01", msg, title);
			}
			else if (StrEqual(title, "Head Admin"))
			{
				Format(msg, maxlen, "%s, \x074D90FC%s\x01", msg, title);
			}
			else if (StrEqual(title, "Media Producer"))
			{
				Format(msg, maxlen, "%s, \x074D90FC%s\x01", msg, title);
			}
			else if (StrEqual(title, "Newswriter"))
			{
				Format(msg, maxlen, "%s, \x079B59B6%s\x01", msg, title);
			}
			else if (StrEqual(title, "Legend"))
			{
				Format(msg, maxlen, "%s, \x07E2DDFF%s\x01", msg, title);
			}
			else
			{
				Format(msg, maxlen, "%s, \x07D0F53B%s\x01", msg, title);
			}
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
			PrintToChat(i, msg);
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

	char title[32];
	kv.GetString("title", title, sizeof(title), "");
	hResult.SetString("title", title);

	char steamID[32];
	if (kv.JumpToKey("steam")) {
		kv.GetString("id", steamID, sizeof(steamID), "");
		kv.GoBack();
	}
	hResult.SetString("SteamId", steamID);


	
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
				if (StrContains(eventName, "Season", false) != -1)
				{
					if (g_hRegExSeason.Match(eventName) > 0) {
					char sYear[4];
					g_hRegExSeason.GetSubString(1, sYear, sizeof(sYear));

					Format(eventName, sizeof(eventName), "Season %s", sYear);
					}
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