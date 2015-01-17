/** Double-include prevention */
#if defined _war_included_
  #endinput
#endif
#define _war_included_

enum WarStatus{
	WS_WAITING,
	WS_INITIALISING,
	WS_PROCESS
};

#if !defined REQUIRE_PLUGIN
public __pl_war_SetNTVOptional()
{
	MarkNativeAsOptional("WAR_SetStatus");
}
#endif

/**
 * Checks if the Player has Freeday.
 *
 * @param NewWarStatus    The new war status.
 * @return        True / False.
 */
native WAR_SetStatus(WarStatus:NewWarStatus);
