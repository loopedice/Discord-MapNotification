#pragma semicolon 1

#include <sourcemod>
#include <regex>
#include <autoexecconfig>
#include <discordWebhookAPI>

#pragma newdecls required

#define LoopValidClients(%1) for(int %1 = 1; %1 <= MaxClients; %1++) if(IsClientValid(%1))
#define MAX_PLAYERS 64  // Adjust as needed

enum struct Global {
    ConVar Webhook;
    ConVar Avatar;
    ConVar Username;
    ConVar Color;
    ConVar LangCode;
    ConVar Game;
    ConVar Logo;
    ConVar Icon;
    ConVar Timestamp;
    ConVar Title;
    ConVar FooterText;
    ConVar RedirectURL;
    ConVar ServerIp;
    ConVar ServerPort;
}

// Define a struct to hold player data
enum struct PlayerInfo {
    char name[MAX_NAME_LENGTH];
    int kills;
    int deaths;
}

PlayerInfo g_Players[MAX_PLAYERS];
int g_PlayerCount = 0;
char messageId[64];

Global Core;

public Plugin myinfo =
{
    name        = "[Discord] Map Notifications",
    description = "Sends a message to your Discord server with information about the current map, players online, and leaderboard.",
    version     = "1.0.2",
    author      = "Bara",
    url         = "https://github.com/Bara"
};

public void OnPluginStart()
{
    LoadTranslations("discord_mapnotification.phrases");

    AutoExecConfig_SetCreateDirectory(true);
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("discord.mapnotifications");
    Core.Webhook = AutoExecConfig_CreateConVar("discord_map_notification_webhook", "MapNotification", "Discord webhook name for this plugin (addons/sourcemod/configs/DMN_Discord.cfg)");
    Core.Avatar = AutoExecConfig_CreateConVar("discord_map_notification_avatar", "https://csgottt.com/map_notification.png", "URL to Avatar image");
    Core.Username = AutoExecConfig_CreateConVar("discord_map_notification_username", "Map Notifications", "Discord username");
    Core.Color = AutoExecConfig_CreateConVar("discord_map_notification_colors", "16738740", "Decimal color code");
    Core.LangCode = AutoExecConfig_CreateConVar("discord_map_notification_language_code", "en", "Language code for Discord messages.");
    Core.Game = AutoExecConfig_CreateConVar("discord_map_notification_game", "csgo", "Game directory for images.");
    Core.Logo = AutoExecConfig_CreateConVar("discord_custom_logo_url", "", "Custom logo for Discord embed.");
    Core.Icon = AutoExecConfig_CreateConVar("discord_map_notification_icon", "https://csgottt.com/map_notification.png", "Footer icon URL.");
    Core.Timestamp = AutoExecConfig_CreateConVar("discord_map_notification_timestamp", "1", "Show timestamp in footer? (0 - No, 1 - Yes)", _, true, 0.0, true, 1.0);
    Core.Title = AutoExecConfig_CreateConVar("discord_map_notification_title", "Custom title", "Set a custom title or leave blank for hostname.");
    Core.FooterText = AutoExecConfig_CreateConVar("discord_map_notification_footer", "Here's the custom footer text.", "Set a custom footer text or leave blank for hostname.");
    Core.RedirectURL = AutoExecConfig_CreateConVar("discord_map_notification_redirect", "https://server.bara.dev/redirect.php", "Redirect URL.");
    Core.ServerIp = AutoExecConfig_CreateConVar("discord_map_notification_server_ip", "", "Set custom server IP.");
    Core.ServerPort = AutoExecConfig_CreateConVar("discord_map_notification_server_port", "0", "Set custom server port.", _, true, 0.0);
    
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();

    RegAdminCmd("dmn_test", Command_Test, ADMFLAG_ROOT);
}

Handle g_Timer = null;

public void OnMapStart()
{
    LogMessage("OnMapStart");

    if (g_Timer != null)
    {
        KillTimer(g_Timer);
    }
    
    g_Timer = CreateTimer(15.0, Timer_PrepareMessage, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Command_Test(int client, int args)
{
    PrepareAndSendMessage(true);
    return Plugin_Stop;
}

public Action Timer_PrepareMessage(Handle timer)
{
    LogMessage("Timer executed: Preparing Discord Message.");  // Debug message
    PrepareAndSendMessage(false);
    return Plugin_Continue;  // Allow the timer to keep repeating
}


// Sort players by kills (descending)
void SortPlayersByKills()
{
    for (int i = 0; i < g_PlayerCount - 1; i++)
    {
        for (int j = 0; j < g_PlayerCount - i - 1; j++)
        {
            if (g_Players[j].kills < g_Players[j + 1].kills)
            {
                // Manually copy struct instead of direct assignment
                PlayerInfo temp;
                strcopy(temp.name, MAX_NAME_LENGTH, g_Players[j].name);
                temp.kills = g_Players[j].kills;
                temp.deaths = g_Players[j].deaths;

                strcopy(g_Players[j].name, MAX_NAME_LENGTH, g_Players[j + 1].name);
                g_Players[j].kills = g_Players[j + 1].kills;
                g_Players[j].deaths = g_Players[j + 1].deaths;

                strcopy(g_Players[j + 1].name, MAX_NAME_LENGTH, temp.name);
                g_Players[j + 1].kills = temp.kills;
                g_Players[j + 1].deaths = temp.deaths;
            }
        }
    }
}

// Main function to collect player stats and send to Discord
void PrepareAndSendMessage(bool test)
{
    g_PlayerCount = 0; // Reset player count

    // Get hostname
    char sHostname[128];
    ConVar cvar = FindConVar("hostname");
    cvar.GetString(sHostname, sizeof(sHostname));

    // Get map name
    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));

    // Get player count
    char playerCount[32];
    Format(playerCount, sizeof(playerCount), "Players: %d/%d", g_PlayerCount, MaxClients);

    // Get clickable link
    char serverIp[64], joinLink[128];
    Core.ServerIp.GetString(serverIp, sizeof(serverIp));
    Format(joinLink, sizeof(joinLink), "[Join Server](steam://connect/%s)", serverIp);


    // Use the 'test' parameter
    if (test)
    {
        Format(sHostname, sizeof(sHostname), "[TEST] %s", sHostname);
    }


    // Collect player data
    LoopValidClients(i)
    {
        if (g_PlayerCount >= MAX_PLAYERS) break; // Prevent overflow

        char sName[MAX_NAME_LENGTH];
        GetClientName(i, sName, sizeof(sName));

        int iKills = GetClientFrags(i);
        int iDeaths = GetClientDeaths(i);

        strcopy(g_Players[g_PlayerCount].name, MAX_NAME_LENGTH, sName);
        g_Players[g_PlayerCount].kills = iKills;
        g_Players[g_PlayerCount].deaths = iDeaths;

        g_PlayerCount++;
    }

    // ? Retrieve the webhook URL before using it
    char sWeb[256], sHook[256];
    Core.Webhook.GetString(sWeb, 256); 

    if (!GetDiscordWebhook(sWeb, sHook, sizeof(sHook)))
    {
        SetFailState("[Map Notification] (PrepareAndSendMessage) Can't find webhook");
        return;
    }

    // Prepare Discord embed
    Webhook wWebhook = new Webhook();
    Embed eEmbed = new Embed();
    eEmbed.SetColor(Core.Color.IntValue);
    eEmbed.SetTitle(sHostname);
    char mapDescription[128];
    FormatEx(mapDescription, sizeof(mapDescription), "Current Map: %s", mapName);
    eEmbed.SetDescription(mapDescription);

    EmbedField ePlayerCount = new EmbedField("Player Count", playerCount, true);
    EmbedField eServerLink = new EmbedField("Join Server", joinLink, false);
    eEmbed.AddField(ePlayerCount);
    eEmbed.AddField(eServerLink);


    if (Core.Timestamp.BoolValue)
    {
        eEmbed.SetTimeStampNow();
    }

    // Format player leaderboard
    char sPlayerList[1024] = ""; 
    char sTemp[128];
    SortPlayersByKills();
    for (int i = 0; i < g_PlayerCount; i++)
    {
        Format(sTemp, sizeof(sTemp), "**%s** - Kills: %d | Deaths: %d\n", 
            g_Players[i].name, g_Players[i].kills, g_Players[i].deaths);
        StrCat(sPlayerList, sizeof(sPlayerList), sTemp);
    }

    if (g_PlayerCount > 0)
    {
        EmbedField ePlayerList = new EmbedField("Leaderboard (Kills/Deaths)", sPlayerList, false);
        eEmbed.AddField(ePlayerList);
    }

    // ? Use the retrieved webhook URL
    wWebhook.AddEmbed(eEmbed);
    if (strcmp(messageId, "")) {
        wWebhook.Execute(sHook, OnWebHookExecuted);
    } else {
        wWebhook.Edit(sHook, messageId, OnWebHookEdited);
    }
    delete wWebhook;
}

public void OnWebHookExecuted(HTTPResponse response, any value)
{
    if (response.Status != HTTPStatus_NoContent && response.Status != HTTPStatus_OK)
    {
        LogError("[Discord.OnWebHookExecuted] Error sending webhook. Status Code: %d", response.Status);
    }
    // Retrieve the message's id.
    JSONObject resData = view_as<JSONObject>(response.Data);
    resData.GetString("id", messageId, sizeof messageId);
}

void OnWebHookEdited(HTTPResponse response, any value)
{
  if (response.Status != HTTPStatus_OK)
  {
    LogError("[Discord.OnWebHookExecuted] Error editing webhook. Status Code: %d", response.Status);
    return;
  }
}

bool IsClientValid(int client)
{
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && !IsClientSourceTV(client));
}

bool GetDiscordWebhook(const char[] sWebhook, char[] sUrl, int iLength)
{
    KeyValues kvWebhook = new KeyValues("Discord");

    char sFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sFile, sizeof(sFile), "configs/DMN_Discord.cfg");

    if (!FileExists(sFile))
    {
        SetFailState("[Map Notification] (GetDiscordWebhook) \"%s\" not found!", sFile);
        delete kvWebhook;
        return false;
    }

    if (!kvWebhook.ImportFromFile(sFile))
    {
        SetFailState("[Map Notification] (GetDiscordWebhook) Can't read: \"%s\"!", sFile);
        delete kvWebhook;
        return false;
    }

    kvWebhook.GetString(sWebhook, sUrl, iLength, "default");

    delete kvWebhook;
    return strlen(sUrl) > 2; // Returns true if webhook URL is valid
}

