#include <amxmodx>
#include <reapi>
#include <sqlx>
#include <hns_matchsystem_sql>

enum _:skill_info {
	skill_pts,
	skill_lvl[10]
};

new const g_eSkillData[][skill_info] = {
	// pts     skill
	{ 0,		"L-" },
	{ 650,		"L" },
	{ 750,		"L+" },
	{ 850,		"M-" },
	{ 950,		"M" },
	{ 1050,		"M+" },
	{ 1150,		"H-" },
	{ 1250,		"H" },
	{ 1350,		"H+" },
	{ 1450,		"P-" },
	{ 1550,		"P" },
	{ 1650,		"P+" },
	{ 1750,		"G-" },
	{ 1850,		"G" },
	{ 1950,		"G+" },
};

enum _:SQL {
	sql_table,
	sql_insert,
	sql_select,
	sql_rank,
	sql_winners,
	sql_loosers
};

enum _:PointsData_s {
	pts,
	wins,
	loss,
	rank,
	skill[10]
};

const PTS_WIN = 15;
const PTS_LOSS = 10;

//new const g_szLinkPts[] = "https://cshnsru.myarena.site/pts/pts.php";
new const g_szTablePts[] = "hns_pts";

new g_sPrefix[24] = ">";
new g_sTablePlayers[32];
new g_ePointsData[MAX_PLAYERS + 1][PointsData_s];

new Handle:g_hSqlTuple;

public plugin_init() {
	register_plugin("Pts", "1.0", "Garey, OpenHNS");

	register_clcmd("say /rank", "CmdRank");
	//register_clcmd("say /pts", "CmdPts");
}

public CmdRank(id) {
	client_print_color(id, print_team_blue, "%s Your rank is ^3%d^1 (Pts: ^3%d^1 | Wins: ^3%d^1 | Loss: ^3%d^1 | Skill: ^3%s^1)", g_sPrefix, g_ePointsData[id][rank], g_ePointsData[id][pts], g_ePointsData[id][wins], g_ePointsData[id][loss], get_skill_player(g_ePointsData[id][pts]));
}

/*public CmdPts(id) {
	new szMotd[MAX_MOTD_LENGTH];

	formatex(szMotd, sizeof(szMotd) - 1,\
	"<html><head><meta http-equiv=^"Refresh^" content=^"0;url=%s^"></head><body><p><center>LOADING...</center></p></body></html>",\
	g_szLinkPts);

	show_motd(id, szMotd);
}*/

public plugin_cfg() {
	hns_sql_get_table_name(g_sTablePlayers, charsmax(g_sTablePlayers));
}

public plugin_natives() {
	register_native("hns_pts_get_player_info", "native_pts_get_player_info");

	register_native("hns_set_pts", "native_set_pts");
}

public native_pts_get_player_info(amxx, params) {
	enum { id = 1, info };
	return g_ePointsData[get_param(id)][get_param(info)];
}

public native_set_pts(TeamName:team_winners) {
	client_print_color(0, print_team_blue, "%s", team_winners);
	SQL_SetPts(team_winners == TEAM_TERRORIST ? TEAM_TERRORIST : TEAM_CT); // Давай птс
}

public hns_sql_player_authorized(id) {
	SQL_Select(id);
}

public hns_sql_connection(Handle:hSqlTuple) {
	g_hSqlTuple = hSqlTuple;

	new szQuery[512];
	new cData[1] = sql_table;
	
	formatex(szQuery, charsmax(szQuery), "\
		CREATE TABLE IF NOT EXISTS `%s` \
		( \
			`player_id`		INT(11) NOT NULL PRIMARY KEY, \
			`wins`			INT(11) NOT NULL DEFAULT 0, \
			`loss`			INT(11) NOT NULL DEFAULT 0, \
			`pts`			INT(11) NOT NULL DEFAULT 1000 \
		);", g_szTablePts);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

public QueryHandler(iFailState, Handle:hQuery, szError[], iErrnum, cData[], iSize, Float:fQueueTime) {
	if (iFailState != TQUERY_SUCCESS) {
		log_amx("SQL Error #%d - %s", iErrnum, szError);
		return;
	}

	switch(cData[0]) {
		case sql_select: {
			new id = cData[1];

			if (SQL_NumResults(hQuery)) {
				new index_wins = SQL_FieldNameToNum(hQuery, "wins");
				new index_loss = SQL_FieldNameToNum(hQuery, "loss");
				new index_pts = SQL_FieldNameToNum(hQuery, "pts");

				g_ePointsData[id][wins] = SQL_ReadResult(hQuery, index_wins);
				g_ePointsData[id][loss] = SQL_ReadResult(hQuery, index_loss);
				g_ePointsData[id][pts] = SQL_ReadResult(hQuery, index_pts);

				SQL_Rank(id);
			} else {
				arrayset(g_ePointsData[id], 0, PointsData_s);
				SQL_Insert(id);
			}
		}
		case sql_insert: {
			new id = cData[1];

			if (!is_user_connected(id))
				return;

			SQL_Rank(id);
		}
		case sql_rank: {
			new id = cData[1];

			if (!is_user_connected(id))
				return;

			if (SQL_NumResults(hQuery)) {
				g_ePointsData[id][rank] = SQL_ReadResult(hQuery, 0);
				g_ePointsData[id][skill] = get_skill_player(g_ePointsData[id][pts]);
			}
		}
		case sql_winners, sql_loosers: {
			for(new i = 1; i <= MaxClients; i++) {
				if (!is_user_connected(i))
					continue;

				if (get_member(i, m_iTeam) == TEAM_SPECTATOR)
					continue;
				
				SQL_Rank(i);
			}
		}
	}
}

SQL_SetPts(TeamName:team_winners) {
	new szQuery[1024], iLen;
	
	new cData[2]; 
	cData[0] = sql_winners;

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "e", team_winners == TEAM_TERRORIST ? "TERRORIST" : "CT");

	if (iNum) {
		for(new i, szAuthId[MAX_AUTHID_LENGTH]; i < iNum; i++) {
			new iWinner = iPlayers[i];
			get_user_authid(iWinner, szAuthId, charsmax(szAuthId));

			g_ePointsData[iWinner][wins]++;
			g_ePointsData[iWinner][pts] += PTS_WIN;

			iLen += formatex(szQuery[iLen], charsmax(szQuery)-iLen, "\
				UPDATE `%s` \
				SET	`wins` = `wins` + 1, `pts` = `pts` + %d \
				WHERE  `player_id` IN \
				( \
					SELECT `id` \
					FROM   `%s` \
					WHERE  `player_steamid` = '%s' \
				); ", g_szTablePts, PTS_WIN, g_sTablePlayers, szAuthId);
		}
		SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));

		szQuery = "";
		iLen = 0;
	}

	get_players(iPlayers, iNum, "e", team_winners == TEAM_TERRORIST ? "CT" : "TERRORIST");

	if (iNum) {
		for(new i, szAuthId[MAX_AUTHID_LENGTH]; i < iNum; i++) {
			new iLooser = iPlayers[i];
			get_user_authid(iLooser, szAuthId, charsmax(szAuthId));

			g_ePointsData[iLooser][loss]++;
			g_ePointsData[iLooser][pts] -= PTS_WIN;

			iLen += formatex(szQuery[iLen], charsmax(szQuery)-iLen, "\
				UPDATE `%s` \
				SET	`loss` = `loss` + 1, `pts` = `pts` - %d \
				WHERE  `player_id` IN \
				( \
					SELECT `id` \
					FROM   `%s` \
					WHERE  `player_steamid` = '%s' \
				); ", g_szTablePts, PTS_LOSS, g_sTablePlayers, szAuthId);
		}
		SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
	}
}

public SQL_Select(id) {
	if (!is_user_connected(id))
		return;

	new szQuery[512];
	new cData[2]; 

	cData[0] = sql_select;
	cData[1] = id;

	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	formatex(szQuery, charsmax(szQuery), "\
		SELECT * \
		FROM `%s` \
		WHERE `player_id` = \
		( \
			SELECT `id` \
			FROM   `hns_players` \
			WHERE  `player_steamid` = '%s' \
		);", g_szTablePts, szAuthId);
	//log_amx(szQuery);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

public SQL_Insert(id) {
	new szQuery[512];
	new cData[2];

	cData[0] = sql_insert;
	cData[1] = id;

	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	formatex(szQuery, charsmax(szQuery), "\
		INSERT INTO `%s` \
		( \
			player_id \
		) \
		VALUES \
		( \
			%d \
		)", g_szTablePts, hns_sql_get_player_id(id));
	//log_amx(szQuery);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

public SQL_Rank(id) {
	new szQuery[512];
	new cData[2]; 
	
	cData[0] = sql_rank;
	cData[1] = id;

	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	formatex(szQuery, charsmax(szQuery), "\
		SELECT COUNT(*) \
		FROM `%s` \
		WHERE `pts` >= %d", g_szTablePts, g_ePointsData[id][pts], hns_sql_get_player_id(id));
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

stock get_skill_player(iPts) {
	new iPtr[10];
	for(new i; i < sizeof(g_eSkillData); i++) {
		if (iPts >= g_eSkillData[i][skill_pts]) {
			formatex(iPtr, charsmax(iPtr), "%s", g_eSkillData[i][skill_lvl]);
		}
	}
	return iPtr;
}
