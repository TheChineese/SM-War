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
 * Set a new war status.
 *
 * @param 		  The new war status.
 * @return        No return
 */
native WAR_SetStatus(WarStatus:NewWarStatus);

/**
 * Set the minimum rounds till war.
 *
 * @param 		  Minimum number of rounds without war.
 * @return        No return
 */
native WAR_SetMinNoWarRounds(any:MinNoWarRounds);

/**
 * Set the number of current war rounds.
 *
 * @param         Number of war rounds.
 * @return        No return
 */
native WAR_SetWarRounds(any:WarRounds);

/**
 * Get the number of current war rounds.
 *
 * @param         No params
 * @return        Number of current war round.
 */
native War_GetRounds();

/**
 * Is war?
 *
 * @param         No params
 * @return        True / False.
 */
native War_IsWar();

/**
 * Is war getting initialised?
 *
 * @param         No params
 * @return        True / False.
 */
native War_IsInit();

/**
 * Is war cooldown?
 *
 * @param         No params
 * @return        True / False.
 */
native War_Cooldown();


/**
 * Called when a war rond is starting
 */

 forward WAR_OnStatusChanged(WarStatus:OldStatus, WarStatus:NewStatus);

 forward WAR_OnCooldown();

 forward WAR_OnTimeLimit();

 forward WAR_OnWarRound(any:WarRound);