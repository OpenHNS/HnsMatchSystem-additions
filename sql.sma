#include <amxmodx>
#include <reapi>
#include <sqlx>

new g_szTablePlayers[] = "hns_players";

enum _:CVARS {
	host[48],
	user[32],
	pass[32],
	db[32]
};

enum _:SQL {
	sql_table,
	sql_select,
	sql_insert,
	sql_name,
	sql_ip
};

new g_eCvars[CVARS];
new Handle:g_hSqlTuple;
new g_hSqlForward;
new g_hAuthorizedForward;
new g_iPlayerID[MAX_PLAYERS + 1];

public plugin_init() {
	register_plugin("Sql", "1.0", "Garey, OpenHNS");

	registerCvars();
	registerForwards();
	registerSQL();

	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "rgSetClientUserInfoName", true);
}

public client_putinserver(id) {
	SQL_Select(id);
}

public plugin_end() {
	SQL_FreeHandle(g_hSqlTuple);
}

public plugin_natives() {
	register_native("hns_sql_get_table_name", "native_sql_get_table_name");
	register_native("hns_sql_get_player_id", "native_sql_get_player_id");
}

public native_sql_get_table_name(amxx, params) {
	enum { table_name = 1, len };
	set_string(table_name, g_szTablePlayers, get_param(len));
}

public native_sql_get_player_id(amxx, params) {
	enum { id = 1 };
	return g_iPlayerID[get_param(id)];
}

registerCvars() {
	new pCvar;
	pCvar = create_cvar("hns_host", "127.0.0.1", FCVAR_PROTECTED, "Host");
	bind_pcvar_string(pCvar, g_eCvars[host], charsmax(g_eCvars[host]));

	pCvar = create_cvar("hns_user", "root", FCVAR_PROTECTED, "User");
	bind_pcvar_string(pCvar, g_eCvars[user], charsmax(g_eCvars[user]));

	pCvar = create_cvar("hns_pass", "root", FCVAR_PROTECTED, "Password");
	bind_pcvar_string(pCvar, g_eCvars[pass], charsmax(g_eCvars[pass]));

	pCvar = create_cvar("hns_db", "hns", FCVAR_PROTECTED, "db");
	bind_pcvar_string(pCvar, g_eCvars[db], charsmax(g_eCvars[db]));

	AutoExecConfig(true, "hnsmatch-sql");

	new szPath[PLATFORM_MAX_PATH]; 
	get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
	
	server_cmd("exec %s/plugins/hnsmatch-sql.cfg", szPath);
	server_exec();
}

registerSQL() {
	g_hSqlTuple = SQL_MakeDbTuple(g_eCvars[host], g_eCvars[user], g_eCvars[pass], g_eCvars[db]);
	SQL_SetCharset(g_hSqlTuple, "utf-8");
	ExecuteForward(g_hSqlForward, _, g_hSqlTuple);

	new szQuery[512];
	new cData[1] = sql_table;
	formatex(szQuery, charsmax(szQuery), "\
		CREATE TABLE IF NOT EXISTS `%s` \
		( \
			`id`				INT(11) NOT NULL auto_increment PRIMARY KEY, \
			`player_name`		VARCHAR(32) NULL DEFAULT NULL, \
			`player_steamid`	VARCHAR(24) NULL DEFAULT NULL, \
			`player_ip`			VARCHAR(22) NULL DEFAULT NULL \
		);", g_szTablePlayers);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

registerForwards() {
	g_hSqlForward = CreateMultiForward("hns_sql_connection", ET_CONTINUE, FP_CELL);
	g_hAuthorizedForward = CreateMultiForward("hns_sql_player_authorized", ET_CONTINUE, FP_CELL);
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
				new index_id = SQL_FieldNameToNum(hQuery, "id");
				new index_name = SQL_FieldNameToNum(hQuery, "player_name");
				new index_ip = SQL_FieldNameToNum(hQuery, "player_ip");

				g_iPlayerID[id] = SQL_ReadResult(hQuery, index_id);

				new szNewName[MAX_NAME_LENGTH * 2];
				SQL_QuoteString(Empty_Handle, szNewName, charsmax(szNewName), fmt("%n", id));

				new szOldName[MAX_NAME_LENGTH];
				SQL_ReadResult(hQuery, index_name, szOldName, charsmax(szOldName));

				if (!equal(szNewName, szOldName))
					SQL_Name(id, szNewName);
				
				new szNewIp[MAX_IP_LENGTH]; 
				get_user_ip(id, szNewIp, charsmax(szNewIp), true);

				new szOldIp[MAX_NAME_LENGTH]; 
				SQL_ReadResult(hQuery, index_ip, szOldIp, charsmax(szOldIp));

				if (!equal(szNewIp, szOldIp))
					SQL_Ip(id, szNewIp);

				ExecuteForward(g_hAuthorizedForward, _, id);
			} else {
				SQL_Insert(id);
			}
		}
		case sql_insert: {
			new id = cData[1];
			g_iPlayerID[id] = SQL_GetInsertId(hQuery);

			ExecuteForward(g_hAuthorizedForward, _, id);
		}
	}
}

public SQL_Select(id) {
	new szQuery[512];

	new cData[2];
	cData[0] = sql_select, 
	cData[1] = id;

	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	formatex(szQuery, charsmax(szQuery), "\
		SELECT * \
		FROM `%s` \
		WHERE `player_steamid` = '%s'", g_szTablePlayers, szAuthId);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

public SQL_Insert(id) {
	new szQuery[512];

	new cData[2];
	cData[0] = sql_insert,
	cData[1] = id;

	new szName[MAX_NAME_LENGTH * 2];
	SQL_QuoteString(Empty_Handle, szName, charsmax(szName), fmt("%n", id));

	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	new szIp[MAX_IP_LENGTH];
	get_user_ip(id, szIp, charsmax(szIp), true);

	formatex(szQuery, charsmax(szQuery), "\
		INSERT INTO `%s` \
		( \
			player_name, \
			player_steamid, \
			player_ip \
		) \
		VALUES \
		( \
			'%s', \
			'%s', \
			'%s' \
		)", g_szTablePlayers, szName, szAuthId, szIp);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

SQL_Name(id, szNewname[]) {
	new szQuery[512]
	new cData[1] = sql_name;

	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	new szName[MAX_NAME_LENGTH * 2];
	SQL_QuoteString(Empty_Handle, szName, charsmax(szName), szNewname);

	formatex(szQuery, charsmax(szQuery), "\
		UPDATE `%s` \
		SET	`player_name` = '%s' \
		WHERE  `player_steamid` = '%s'", g_szTablePlayers, szName, szAuthId);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

SQL_Ip(id, szNewip[]) {
	new szQuery[512]
	new cData[1] = sql_ip;

	new szAuthId[MAX_AUTHID_LENGTH];
	get_user_authid(id, szAuthId, charsmax(szAuthId));

	formatex(szQuery, charsmax(szQuery), "\
		UPDATE `%s` \
		SET	`player_ip` = '%s' \
		WHERE  `player_steamid` = '%s'", g_szTablePlayers, szNewip, szAuthId);
	SQL_ThreadQuery(g_hSqlTuple, "QueryHandler", szQuery, cData, sizeof(cData));
}

public rgSetClientUserInfoName(id, infobuffer[], szNewName[]) {
	if (!is_user_connected(id))
		return;

	SQL_Name(id, szNewName);
}