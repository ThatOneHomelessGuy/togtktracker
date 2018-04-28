/** Double-include prevention */
#if defined _togtktracker_included_
  #endinput
#endif
#define _togtktracker_included_
 
/**
 * Return total TKs for client that occured within current map
 *
 * @param	client		Client index
 *
 * @return				Integer number of TKs, -1 if invalid client
 */
native int ttkt_GetTKCnt_Map(int client);

/**
 * Return total TKs for client on record.
 *
 * @param	client		Client index
 *
 * @return				Integer number of TKs, -1 if invalid client, -2 if player hasnt loaded, or -3 if the database isnt loaded yet.
 */
native int ttkt_GetTKCnt_Total(int client);

/* 
 * Called when a client finishes loading from the database.
 * 
 * @param	client		Client index of player that has loaded.
 *
 * @return	None.
 */ 
forward void ttkt_ClientLoaded(int client);

/* 
 * Called when a client TKs someone.
 * 
 * @param	client		Client index of player that committed the TK.
 *
 * @return	None.
 */ 
forward void ttkt_TKEvent(int client);

public SharedPlugin __pl_togtktracker =
{
	name = "togtktracker",
	file = "togtktracker.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_togtktracker_SetNTVOptional()
{
	MarkNativeAsOptional("ttkt_GetTKCnt_Map");
	MarkNativeAsOptional("ttkt_GetTKCnt_Total");
}
#endif