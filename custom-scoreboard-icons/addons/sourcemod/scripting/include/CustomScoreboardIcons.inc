#if defined _ScoreboardCustomLevels_included
  #endinput
#endif
#define _ScoreboardCustomLevels_included

native int SCI_GetClientIconIndex(int client);

public SharedPlugin __pl_server_redirect = 
{
	name = "CustomScoreboardIcons",
	file = "CustomScoreboardIcons.smx",

	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};