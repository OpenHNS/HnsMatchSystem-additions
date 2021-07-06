#if defined _hns_matchsystem_included
	#endinput
#endif
#define _hns_matchsystem_included

enum {
	e_mTraining,
	e_mPaused,
	e_mKnife,
	e_mCaptain,
	e_mMatch,
	e_mPublic,
	e_mDM
}

native hns_get_prefix(prefix[], len);

native hns_get_mode();
native hns_set_mode(mode);