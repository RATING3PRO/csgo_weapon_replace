#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.2.0"
#define MAX_TRACKED_WEAPON_ID 64
#define CHAT_PREFIX "\x04[武器替换]\x01"

public Plugin myinfo =
{
    name = "CS:GO Weapon Replace",
    author = "RATING3PRO",
    description = "Stores a separate set of weapon purchase replacements for every player",
    version = PLUGIN_VERSION,
    url = ""
};

enum ReplaceInputState
{
    ReplaceInput_None = 0,
    ReplaceInput_Source,
    ReplaceInput_Target
};

// These are SourceMod CSWeaponID values. Only actual CS:GO weapons that can be
// created safely with GivePlayerItem are exposed to players.
static const int g_WeaponIds[] =
{
    2, 4, 5, 7, 8, 9, 10, 11, 12, 15,
    17, 18, 19, 21, 24, 25, 27, 29, 34, 35,
    36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
    47, 48, 49, 51, 52, 53, 60, 61, 63, 64
};

static const char g_WeaponAliases[][] =
{
    "glock", "hegrenade", "xm1014", "mac10", "aug", "smokegrenade",
    "elite", "fiveseven", "ump45", "famas", "awp", "mp5sd", "m249",
    "m4a1", "flashbang", "deagle", "ak47", "p90", "galilar", "bizon",
    "mag7", "negev", "sawedoff", "tec9", "taser", "hkp2000", "mp7",
    "mp9", "nova", "p250", "scar20", "sg556", "ssg08", "molotov",
    "decoy", "incgrenade", "m4a1_silencer", "usp_silencer", "cz75a",
    "revolver"
};

static const char g_WeaponNames[][] =
{
    "Glock-18", "HE", "XM1014", "MAC-10", "AUG", "Smoke",
    "Dual Berettas", "Five-SeveN", "UMP-45", "FAMAS", "AWP", "MP5-SD",
    "M249", "M4A4", "Flashbang", "Desert Eagle", "AK-47", "P90",
    "Galil AR", "PP-Bizon", "MAG-7", "Negev", "Sawed-Off", "Tec-9",
    "Zeus x27", "P2000", "MP7", "MP9", "Nova", "P250", "SCAR-20",
    "SG 553", "SSG 08", "Molotov", "Decoy", "Incendiary", "M4A1-S",
    "USP-S", "CZ75-Auto", "R8 Revolver"
};

ReplaceInputState g_InputState[MAXPLAYERS + 1];
int g_PendingSource[MAXPLAYERS + 1];
int g_Replacements[MAXPLAYERS + 1][MAX_TRACKED_WEAPON_ID + 1];

KeyValues g_ReplacementData;
char g_DataPath[PLATFORM_MAX_PATH];
ConVar g_MaxMoney;

public void OnPluginStart()
{
    RegConsoleCmd("sm_replace", Command_Replace, "Configure personal weapon purchase replacements");
    RegConsoleCmd("sm_replacements", Command_ShowReplacements, "Show personal weapon replacement rules");
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");
    HookEvent("item_purchase", Event_ItemPurchase, EventHookMode_Post);
    g_MaxMoney = FindConVar("mp_maxmoney");

    BuildPath(Path_SM, g_DataPath, sizeof(g_DataPath), "data/weapon_replace.cfg");
    g_ReplacementData = new KeyValues("WeaponReplacements");
    g_ReplacementData.ImportFromFile(g_DataPath);

    for (int client = 1; client <= MaxClients; client++)
    {
        ResetClientData(client);
        if (IsClientInGame(client) && !IsFakeClient(client) && IsClientAuthorized(client))
        {
            LoadClientReplacements(client);
        }
    }
}

public void OnPluginEnd()
{
    delete g_ReplacementData;
}

public void OnClientConnected(int client)
{
    ResetClientData(client);
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsFakeClient(client))
    {
        LoadClientReplacements(client);
    }
}

public void OnClientDisconnect(int client)
{
    g_InputState[client] = ReplaceInput_None;
    g_PendingSource[client] = 0;
}

public Action Command_Replace(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[武器替换] 此命令只能由游戏内玩家使用。");
        return Plugin_Handled;
    }

    g_InputState[client] = ReplaceInput_Source;
    g_PendingSource[client] = 0;

    PrintToChat(client, "%s 请输入购买时的武器 ID（例如 \x03weapon_ak47\x01）。", CHAT_PREFIX);
    PrintToChat(client, "%s 输入 \x03list\x01 查看全部 ID，输入 \x03rules\x01 查看已有规则，输入 \x03cancel\x01 取消。", CHAT_PREFIX);
    return Plugin_Handled;
}

public Action Command_ShowReplacements(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[武器替换] 此命令只能由游戏内玩家使用。");
        return Plugin_Handled;
    }

    PrintCurrentRules(client);
    return Plugin_Handled;
}

public Action Command_Say(int client, const char[] command, int argc)
{
    if (client <= 0 || !IsClientInGame(client) || g_InputState[client] == ReplaceInput_None)
    {
        return Plugin_Continue;
    }

    char text[64];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (StrEqual(text, "list", false))
    {
        PrintWeaponList(client);
        PrintCurrentPrompt(client);
        return Plugin_Handled;
    }

    if (StrEqual(text, "rules", false))
    {
        PrintCurrentRules(client);
        PrintCurrentPrompt(client);
        return Plugin_Handled;
    }

    if (StrEqual(text, "cancel", false))
    {
        g_InputState[client] = ReplaceInput_None;
        g_PendingSource[client] = 0;
        PrintToChat(client, "%s 已取消设置。", CHAT_PREFIX);
        return Plugin_Handled;
    }

    char weaponAlias[64];
    strcopy(weaponAlias, sizeof(weaponAlias), text);
    NormalizeWeaponAlias(weaponAlias, sizeof(weaponAlias));
    int weaponId = GetWeaponIdByAlias(weaponAlias);
    if (!IsSupportedWeaponId(weaponId))
    {
        PrintToChat(client, "%s 无效的武器 ID。请使用类似 \x03weapon_ak47\x01 的完整名称，或输入 \x03list\x01。", CHAT_PREFIX);
        return Plugin_Handled;
    }

    if (g_InputState[client] == ReplaceInput_Source)
    {
        g_PendingSource[client] = weaponId;
        g_InputState[client] = ReplaceInput_Target;

        char weaponClassname[48];
        GetWeaponClassname(weaponId, weaponClassname, sizeof(weaponClassname));
        PrintToChat(client, "%s 已选择购买武器 \x03%s\x01。现在请输入替换后的武器 ID。", CHAT_PREFIX, weaponClassname);
        PrintToChat(client, "%s 输入同一个武器 ID 可删除这条替换规则。", CHAT_PREFIX);
        return Plugin_Handled;
    }

    int sourceId = g_PendingSource[client];
    g_InputState[client] = ReplaceInput_None;
    g_PendingSource[client] = 0;

    if (sourceId == weaponId)
    {
        g_Replacements[client][sourceId] = 0;
        SaveClientReplacement(client, sourceId, 0);
        char sourceClassname[48];
        GetWeaponClassname(sourceId, sourceClassname, sizeof(sourceClassname));
        PrintToChat(client, "%s 已删除 \x03%s\x01 的替换规则。", CHAT_PREFIX, sourceClassname);
        return Plugin_Handled;
    }

    g_Replacements[client][sourceId] = weaponId;
    SaveClientReplacement(client, sourceId, weaponId);

    char sourceClassname[48];
    char targetClassname[48];
    GetWeaponClassname(sourceId, sourceClassname, sizeof(sourceClassname));
    GetWeaponClassname(weaponId, targetClassname, sizeof(targetClassname));
    PrintToChat(client, "%s 设置成功：购买 \x03%s\x01 时替换为 \x03%s\x01。", CHAT_PREFIX, sourceClassname, targetClassname);
    return Plugin_Handled;
}

public void Event_ItemPurchase(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
    {
        return;
    }

    char purchasedAlias[32];
    event.GetString("weapon", purchasedAlias, sizeof(purchasedAlias));
    NormalizeWeaponAlias(purchasedAlias, sizeof(purchasedAlias));

    int sourceId = GetWeaponIdByAlias(purchasedAlias);
    if (sourceId <= 0 || sourceId > MAX_TRACKED_WEAPON_ID)
    {
        return;
    }

    int targetId = g_Replacements[client][sourceId];
    if (!IsSupportedWeaponId(targetId) || targetId == sourceId)
    {
        return;
    }

    int sourcePrice = CS_GetWeaponPrice(client, view_as<CSWeaponID>(sourceId), false);
    int targetPrice = CS_GetWeaponPrice(client, view_as<CSWeaponID>(targetId), false);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientSerial(client));
    pack.WriteCell(sourceId);
    pack.WriteCell(targetId);
    pack.WriteCell(sourcePrice);
    pack.WriteCell(targetPrice);
    RequestFrame(Frame_ReplacePurchasedWeapon, pack);
}

public void Frame_ReplacePurchasedWeapon(any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientFromSerial(pack.ReadCell());
    int sourceId = pack.ReadCell();
    int targetId = pack.ReadCell();
    int sourcePrice = pack.ReadCell();
    int targetPrice = pack.ReadCell();
    delete pack;

    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    char sourceClassname[48];
    char targetClassname[48];
    GetWeaponClassname(sourceId, sourceClassname, sizeof(sourceClassname));
    GetWeaponClassname(targetId, targetClassname, sizeof(targetClassname));

    int purchasedEntity = FindOwnedWeaponByClassname(client, sourceClassname);
    if (purchasedEntity == -1)
    {
        // The purchase event can also describe ammo/equipment on some servers.
        // Never grant a free replacement unless the purchased entity exists.
        return;
    }

    int priceDifference = targetPrice - sourcePrice;
    int currentMoney = GetEntProp(client, Prop_Send, "m_iAccount");
    if (priceDifference > 0 && currentMoney < priceDifference)
    {
        PrintToChat(client, "%s 替换为 \x03%s\x01 还需要 $%d，余额不足，已保留原武器。", CHAT_PREFIX, targetClassname, priceDifference);
        return;
    }

    RemovePlayerItem(client, purchasedEntity);
    AcceptEntityInput(purchasedEntity, "Kill");

    int replacementEntity = GivePlayerItem(client, targetClassname);
    if (replacementEntity == -1)
    {
        // Preserve the paid purchase if a server modification rejects the target.
        GivePlayerItem(client, sourceClassname);
        PrintToChat(client, "%s 无法生成替换武器，已恢复原武器。", CHAT_PREFIX);
        return;
    }

    EquipPlayerWeapon(client, replacementEntity);
    int moneyChange = SetReplacementPurchaseMoney(client, currentMoney, priceDifference);

    if (moneyChange > 0)
    {
        PrintToChat(client, "%s 目标武器价格较低，已返还差价 \x04$%d\x01。", CHAT_PREFIX, moneyChange);
    }
    else if (moneyChange < 0)
    {
        PrintToChat(client, "%s 目标武器价格较高，已补扣差价 \x02$%d\x01。", CHAT_PREFIX, -moneyChange);
    }
}

int SetReplacementPurchaseMoney(int client, int moneyAfterPurchase, int priceDifference)
{
    int adjustedMoney = moneyAfterPurchase - priceDifference;
    int maximumMoney = 16000;
    if (g_MaxMoney != null)
    {
        maximumMoney = g_MaxMoney.IntValue;
    }

    if (adjustedMoney < 0)
    {
        adjustedMoney = 0;
    }
    else if (adjustedMoney > maximumMoney)
    {
        adjustedMoney = maximumMoney;
    }

    SetEntProp(client, Prop_Send, "m_iAccount", adjustedMoney);
    return adjustedMoney - moneyAfterPurchase;
}

void ResetClientData(int client)
{
    g_InputState[client] = ReplaceInput_None;
    g_PendingSource[client] = 0;

    for (int weaponId = 0; weaponId <= MAX_TRACKED_WEAPON_ID; weaponId++)
    {
        g_Replacements[client][weaponId] = 0;
    }
}

void LoadClientReplacements(int client)
{
    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true))
    {
        return;
    }

    for (int weaponId = 0; weaponId <= MAX_TRACKED_WEAPON_ID; weaponId++)
    {
        g_Replacements[client][weaponId] = 0;
    }

    g_ReplacementData.Rewind();
    if (!g_ReplacementData.JumpToKey(steamId, false))
    {
        return;
    }

    char key[8];
    for (int i = 0; i < sizeof(g_WeaponIds); i++)
    {
        int sourceId = g_WeaponIds[i];
        IntToString(sourceId, key, sizeof(key));
        int targetId = g_ReplacementData.GetNum(key, 0);
        if (IsSupportedWeaponId(targetId) && targetId != sourceId)
        {
            g_Replacements[client][sourceId] = targetId;
        }
    }

    g_ReplacementData.Rewind();
}

void SaveClientReplacement(int client, int sourceId, int targetId)
{
    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true))
    {
        PrintToChat(client, "%s Steam 身份验证尚未完成，本次设置无法保存。", CHAT_PREFIX);
        return;
    }

    char key[8];
    IntToString(sourceId, key, sizeof(key));

    g_ReplacementData.Rewind();
    g_ReplacementData.JumpToKey(steamId, true);
    if (targetId == 0)
    {
        g_ReplacementData.DeleteKey(key);
    }
    else
    {
        g_ReplacementData.SetNum(key, targetId);
    }
    g_ReplacementData.Rewind();

    if (!g_ReplacementData.ExportToFile(g_DataPath))
    {
        LogError("Unable to write weapon replacement data to %s", g_DataPath);
        PrintToChat(client, "%s 写入配置文件失败，请联系服务器管理员。", CHAT_PREFIX);
    }
}

void PrintWeaponList(int client)
{
    PrintToChat(client, "%s 可用武器 ID（完整列表也已输出到控制台）：", CHAT_PREFIX);
    PrintToConsole(client, "========== CS:GO 武器替换 ID ==========");

    char chatLine[190];
    for (int i = 0; i < sizeof(g_WeaponIds); i++)
    {
        char entry[48];
        Format(entry, sizeof(entry), "weapon_%s", g_WeaponAliases[i]);
        PrintToConsole(client, "%s (%s)", entry, g_WeaponNames[i]);

        if (chatLine[0] != '\0')
        {
            StrCat(chatLine, sizeof(chatLine), " | ");
        }
        StrCat(chatLine, sizeof(chatLine), entry);

        if ((i + 1) % 2 == 0 || i == sizeof(g_WeaponIds) - 1)
        {
            PrintToChat(client, "\x05%s", chatLine);
            chatLine[0] = '\0';
        }
    }
}

void PrintCurrentRules(int client)
{
    int ruleCount = 0;
    PrintToConsole(client, "========== 你的武器替换规则 ==========");

    for (int i = 0; i < sizeof(g_WeaponIds); i++)
    {
        int sourceId = g_WeaponIds[i];
        int targetId = g_Replacements[client][sourceId];
        if (!IsSupportedWeaponId(targetId) || targetId == sourceId)
        {
            continue;
        }

        char sourceClassname[48];
        char targetClassname[48];
        GetWeaponClassname(sourceId, sourceClassname, sizeof(sourceClassname));
        GetWeaponClassname(targetId, targetClassname, sizeof(targetClassname));
        PrintToChat(client, "%s \x03%s\x01 -> \x05%s", CHAT_PREFIX, sourceClassname, targetClassname);
        PrintToConsole(client, "%s -> %s", sourceClassname, targetClassname);
        ruleCount++;
    }

    if (ruleCount == 0)
    {
        PrintToChat(client, "%s 你目前没有保存任何替换规则。", CHAT_PREFIX);
        PrintToConsole(client, "（暂无规则）");
        return;
    }

    PrintToChat(client, "%s 共找到 \x03%d\x01 条个人替换规则。", CHAT_PREFIX, ruleCount);
}

void PrintCurrentPrompt(int client)
{
    if (g_InputState[client] == ReplaceInput_Source)
    {
        PrintToChat(client, "%s 请输入购买时的武器 ID，例如 \x03weapon_ak47\x01。", CHAT_PREFIX);
    }
    else if (g_InputState[client] == ReplaceInput_Target)
    {
        PrintToChat(client, "%s 请输入替换后的武器 ID，例如 \x03weapon_awp\x01。", CHAT_PREFIX);
    }
}

bool IsSupportedWeaponId(int weaponId)
{
    return GetWeaponIndexById(weaponId) != -1;
}

int GetWeaponIndexById(int weaponId)
{
    for (int i = 0; i < sizeof(g_WeaponIds); i++)
    {
        if (g_WeaponIds[i] == weaponId)
        {
            return i;
        }
    }
    return -1;
}

int GetWeaponIdByAlias(const char[] alias)
{
    for (int i = 0; i < sizeof(g_WeaponAliases); i++)
    {
        if (StrEqual(alias, g_WeaponAliases[i], false))
        {
            return g_WeaponIds[i];
        }
    }
    return 0;
}

void GetWeaponClassname(int weaponId, char[] buffer, int maxLength)
{
    int index = GetWeaponIndexById(weaponId);
    if (index == -1)
    {
        buffer[0] = '\0';
        return;
    }
    Format(buffer, maxLength, "weapon_%s", g_WeaponAliases[index]);
}

void NormalizeWeaponAlias(char[] alias, int maxLength)
{
    if (StrContains(alias, "weapon_", false) == 0)
    {
        ReplaceString(alias, maxLength, "weapon_", "", false);
    }

    // Buy aliases used by the game/loadout can differ from entity classnames.
    if (StrEqual(alias, "m4a1_silencer_off", false))
    {
        strcopy(alias, maxLength, "m4a1_silencer");
    }
    else if (StrEqual(alias, "usp_silencer_off", false))
    {
        strcopy(alias, maxLength, "usp_silencer");
    }
}

int FindOwnedWeaponByClassname(int client, const char[] classname)
{
    int weaponCount = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int i = 0; i < weaponCount; i++)
    {
        int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (entity <= MaxClients || !IsValidEntity(entity))
        {
            continue;
        }

        char entityClassname[48];
        GetEntityClassname(entity, entityClassname, sizeof(entityClassname));
        if (StrEqual(entityClassname, classname, false))
        {
            return entity;
        }
    }
    return -1;
}
