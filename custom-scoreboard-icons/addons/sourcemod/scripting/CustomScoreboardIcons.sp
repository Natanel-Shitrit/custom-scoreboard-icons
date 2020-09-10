#include <sourcemod>
#include <clientprefs>
#include <multicolors>
#include <sdkhooks>
#include <sdktools>

#define PREFIX " \x04[Custom-Icons]\x01"
#define PREFIX_MENU "[Custom-Icons]"

#define STEAMID_LENGTH 32

ConVar g_cvSaveIcons;

Cookie g_hPlayerIconCookie = null;

enum struct Icon
{
	char Name[64];
	int Index;
	
	ArrayList alPlayersWithAccess;
	
	void Init()
	{
		this.alPlayersWithAccess = new ArrayList(ByteCountToCells(STEAMID_LENGTH));
	}
	
	void Close()
	{
		if(this.alPlayersWithAccess)
			delete this.alPlayersWithAccess;
	}
	
	void AddPlayerToAccessList(const char[] sClientSteamID64)
	{
		this.alPlayersWithAccess.PushString(sClientSteamID64);
	}
	
	bool CheckClientAccess(int client)
	{
		char sClientSteamID64[32];
		GetClientAuthId(client, AuthId_Steam2, sClientSteamID64, sizeof(sClientSteamID64));
		
		return (this.alPlayersWithAccess.FindString(sClientSteamID64) != -1);
	}
}
ArrayList g_alIcons;

int g_iClientIcon[MAXPLAYERS + 1];
int m_nPersonaDataPublicLevel = -1;

public Plugin myinfo = 
{
	name = "[Core] Custom Scoreboard Icons", 
	author = "Original idea by Nexd, Recreated by LuqS", 
	description = "Gives you the ability to add custom 'Levels' (Images / Icons) To the client scoreboad", 
	version = "2.0", 
	url = "Original: https://github.com/KillStr3aK --------- Recreated: https://github.com/Natanel-Shitrit || https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

public void OnPluginStart()
{
	g_alIcons = new ArrayList(sizeof(Icon));
	
	// The offset of 'm_nPersonaDataPublicLevel', This will give us the ability to change the image.
	m_nPersonaDataPublicLevel = FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel");
	
	// Save Icons?
	g_cvSaveIcons = CreateConVar("custom_icons_save", "1", "Whether or not to save the client's selected icon.");
	
	// Open icons menu.
	RegConsoleCmd("sm_icons", Command_Icons);
	
	// Here we are going to save the icons players used
	g_hPlayerIconCookie = view_as<Cookie>(RegClientCookie("csi_client_icon", "The client's selected icon", CookieAccess_Private));
	
	// Late load support
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		if (AreClientCookiesCached(iCurrentClient))
			OnClientCookiesCached(iCurrentClient);
}

public void OnPluginEnd()
{
	// Save on unload
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		if (AreClientCookiesCached(iCurrentClient))
			OnClientDisconnect(iCurrentClient);
}

public void OnClientCookiesCached(int client)
{
	if(!g_cvSaveIcons.BoolValue)
		return;
	
	// Get Clienbt Cookie Value
	char sClientCookieValue[8];
	g_hPlayerIconCookie.Get(client, sClientCookieValue, sizeof(sClientCookieValue));
	
	// Save it
	g_iClientIcon[client] = StringToInt(sClientCookieValue);
}

public Action Command_Icons(int client, int args)
{
	if((0 < client <= MaxClients) && IsClientInGame(client))
		OpenIconsMenu(client);
		
	return Plugin_Handled;
}

void OpenIconsMenu(int client, int start = 0)
{
	Menu menu = new Menu(IconsMenuHandler);
	menu.SetTitle("%s Change Icon\n ", PREFIX_MENU);
	
	menu.AddItem("", "Reset Icon", g_iClientIcon[client] != -1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Icon currentIcon;
	char sIconIndex[16], sDisplayBuffer[64];
	for (int iCurrentIcon = 0; iCurrentIcon < g_alIcons.Length; iCurrentIcon++)
	{
		// Get the Icon info from the ArrayList.
		currentIcon = GetIconByIndex(iCurrentIcon);
		
		IntToString(currentIcon.Index, sIconIndex, sizeof(sIconIndex));
		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "%s %s", currentIcon.Name, (!currentIcon.alPlayersWithAccess.Length || currentIcon.CheckClientAccess(client)) ? (g_iClientIcon[client] == currentIcon.Index ? "[SELECTED]" : "") : "[NO ACCESS]");
		
		menu.AddItem(sIconIndex, sDisplayBuffer, ((!currentIcon.alPlayersWithAccess.Length || currentIcon.CheckClientAccess(client)) && g_iClientIcon[client] != currentIcon.Index) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	menu.DisplayAt(client, start, MENU_TIME_FOREVER);
}

int IconsMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			// If the client pressed the 'Reset' button 
			if(!param2)
				ChangePlayerIcon(client, -1);
			else
			{
				char sIconIndex[10];
				menu.GetItem(param2, sIconIndex, sizeof(sIconIndex));
				
				// Change to the icon the player selected.
				ChangePlayerIcon(client, StringToInt(sIconIndex));
			}
			
			// Re-Open the menu.
			OpenIconsMenu(client, menu.Selection);
		}
		case MenuAction_End:
			delete menu;
	}
}

void ChangePlayerIcon(int client, int iconindex)
{
	// Equip the Icon
	g_iClientIcon[client] = iconindex;
	
	// Print the message
	if(iconindex != -1)
		CPrintToChat(client, "%s You've equipped the {green}%s {default}icon!", PREFIX, GetIconFromIconIndex(iconindex).Name);
	else
		CPrintToChat(client, "%s You've {green}Rested {default}your icon!", PREFIX);
}

public void OnMapStart()
{
	// Hooking Resouce Entity
	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, OnThinkPost);
	
	// Close all old ArrayLists
	for (int iCurrentIcon = 0; iCurrentIcon < g_alIcons.Length; iCurrentIcon++)
		GetIconByIndex(iCurrentIcon).Close();
	
	// Clear the ArrayList
	g_alIcons.Clear();
	
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("CustomIcons");
	
	// Find the Config
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/CustomIcons/custom_icons.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if(!kv.ImportFromFile(sFilePath) || !kv.GotoFirstSubKey())
		SetFailState("%s Couldn't load plugin config.", PREFIX_MENU);
	
	// Parse Icons one by one.
	do
	{
		Icon newIcon;
		
		// Find the index
		newIcon.Index = kv.GetNum("index");
		
		// Find the icon name
		kv.GetString("name", newIcon.Name, sizeof(newIcon.Name));
		
		// Create the Players ArrayList
		newIcon.Init();
		
		// Add all SteamIDs (Must be SteamID64)
		if(kv.JumpToKey("players"))
		{
			char sClientSteamID[STEAMID_LENGTH];
			
			if(kv.GotoFirstSubKey(false))
			{
				do
				{
					kv.GetString(NULL_STRING, sClientSteamID, sizeof(sClientSteamID));
					newIcon.AddPlayerToAccessList(sClientSteamID);
					
				} while (kv.GotoNextKey());
				
				kv.GoBack();
			}
			
			kv.GoBack();
		}
		
		g_alIcons.PushArray(newIcon, sizeof(newIcon));
		
	} while (kv.GotoNextKey());
	
	// Don't leak handles.
	kv.Close();
	
	// Add all icons to the download table
	AddDirectoryToDownloadTable("materials/panorama/images/icons/xp");
}

public void OnThinkPost(int m_iEntity)
{
	int m_iCurrentIcons[MAXPLAYERS + 1] = 0;
	GetEntDataArray(m_iEntity, m_nPersonaDataPublicLevel, m_iCurrentIcons, MAXPLAYERS + 1);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (g_iClientIcon[iCurrentClient] > 0)
		{
			if (g_iClientIcon[iCurrentClient] != m_iCurrentIcons[iCurrentClient])
				SetEntData(m_iEntity, m_nPersonaDataPublicLevel + (iCurrentClient * 4), g_iClientIcon[iCurrentClient]);
		}
		else
			SetEntData(m_iEntity, m_nPersonaDataPublicLevel + (iCurrentClient * 4), -1);
	}
}

public void OnClientDisconnect(int client)
{
	if(g_cvSaveIcons.BoolValue)
	{
		char sIconIndex[8];
		IntToString(g_iClientIcon[client], sIconIndex, sizeof(sIconIndex));
		
		// Change cookie value
		g_hPlayerIconCookie.Set(client, sIconIndex);
	}
	
	// Reset local variable
	g_iClientIcon[client] = -1;
}

any[] GetIconByIndex(int index)
{
	Icon icon;
	g_alIcons.GetArray(index, icon, sizeof(icon));
	
	return icon;
}

void AddDirectoryToDownloadTable(char[] sDirectory)
{
    char sPath[PLATFORM_MAX_PATH], sFileAfter[PLATFORM_MAX_PATH];
    FileType fileType;
    
    Handle dir = OpenDirectory(sDirectory);
    
    if (dir != INVALID_HANDLE)
    {
    	while (ReadDirEntry(dir, sPath, sizeof(sPath), fileType))
	    {
	        FormatEx(sFileAfter, sizeof(sFileAfter), "%s/%s", sDirectory, sPath);
	        if (fileType == FileType_File)
	            AddFileToDownloadsTable(sFileAfter);
	    }
    }
    
    delete dir;
}

int GetIconFromIconIndex(int iconindex)
{
	Icon currentIcon;
	for (int iCurrentIcon = 0; iCurrentIcon < g_alIcons.Length; iCurrentIcon++)
	{
		currentIcon = GetIconByIndex(iCurrentIcon);
		if(currentIcon.Index == iconindex)
			return currentIcon;
	}
	
	return currentIcon;
}

// NATIVES

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("CustomScoreboardIcons");
	CreateNative("SCI_GetClientIconIndex", Native_GetIconIndex);
	
	// TODO: Add Native
	//CreateNative("SCI_SetIconIndex", Native_SetIconIndex);
	
	return APLRes_Success;
}

public Native_GetIconIndex(Handle plugin, int params)
{
	return g_iClientIcon[GetNativeCell(1)];
}