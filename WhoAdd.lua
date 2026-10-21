-- WhoAdd.lua
-- 首拉通报、开怪快照与首领数据
-- 兼容 _classic_titan_ / WotLK 3.3.5 风格 API

local addonName = ...

local WhoAdd = CreateFrame("Frame")
local WhoAddVersion = "4.6.10"
WhoAdd.loadStage = "初始化"
_G.WhoAddVersion = WhoAddVersion

-- 兜底命令：如果后续界面初始化报错，至少给出明确提示而不是毫无反应。
SLASH_WHOADD1 = "/wadd"
SLASH_WHOADD2 = "/whoadd"
SlashCmdList["WHOADD"] = function()
    print("|cffff4444[WhoAdd]|r 插件加载未完成，错误阶段：" .. tostring(WhoAdd.loadStage or "未知") ..
        "。请检查 Lua 报错后执行 /reload")
end

pcall(WhoAdd.RegisterEvent, WhoAdd, "ADDON_LOADED")
pcall(WhoAdd.RegisterEvent, WhoAdd, "PLAYER_ENTERING_WORLD")
pcall(WhoAdd.RegisterEvent, WhoAdd, "PLAYER_LOGOUT")
pcall(WhoAdd.RegisterEvent, WhoAdd, "GROUP_ROSTER_UPDATE")
pcall(WhoAdd.RegisterEvent, WhoAdd, "UNIT_PET")
pcall(WhoAdd.RegisterEvent, WhoAdd, "PLAYER_REGEN_ENABLED")
pcall(WhoAdd.RegisterEvent, WhoAdd, "PLAYER_REGEN_DISABLED")
pcall(WhoAdd.RegisterEvent, WhoAdd, "UNIT_FLAGS")
pcall(WhoAdd.RegisterEvent, WhoAdd, "UNIT_TARGET")
pcall(WhoAdd.RegisterEvent, WhoAdd, "PLAYER_TARGET_CHANGED")
pcall(WhoAdd.RegisterEvent, WhoAdd, "UPDATE_MOUSEOVER_UNIT")
pcall(WhoAdd.RegisterEvent, WhoAdd, "GOSSIP_SHOW")
pcall(WhoAdd.RegisterEvent, WhoAdd, "NAME_PLATE_UNIT_ADDED")
pcall(WhoAdd.RegisterEvent, WhoAdd, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
pcall(WhoAdd.RegisterEvent, WhoAdd, "ENCOUNTER_START")
pcall(WhoAdd.RegisterEvent, WhoAdd, "ENCOUNTER_END")
pcall(WhoAdd.RegisterEvent, WhoAdd, "ZONE_CHANGED_NEW_AREA")
pcall(WhoAdd.RegisterEvent, WhoAdd, "COMBAT_LOG_EVENT_UNFILTERED")

-- ============================================================
-- 基础常量
-- ============================================================

local OBJ_AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
local OBJ_AFFILIATION_PARTY = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
local OBJ_AFFILIATION_RAID = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004
local OBJ_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local OBJ_TYPE_NPC = COMBATLOG_OBJECT_TYPE_NPC or 0x00000800
local OBJ_TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x00001000
local OBJ_TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000
local OBJ_TYPE_VEHICLE = COMBATLOG_OBJECT_TYPE_VEHICLE or 0x00004000
local OBJ_REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local AFFILIATION_GROUP_MASK = OBJ_AFFILIATION_MINE + OBJ_AFFILIATION_PARTY + OBJ_AFFILIATION_RAID

local ROLE_LABELS = {
    TANK    = "坦克",
    HEALER  = "治疗",
    DAMAGER = "输出",
    DPS     = "输出",
    NONE    = "未分配",
}

local TYPE_LABELS = {
    boss     = "首领",
    add      = "关联小怪",
    opening  = "开怪NPC",
    dialogue = "对话开怪",
    trash    = "普通怪物",
}

local SOURCE_LABELS = {
    SCAN       = "目标扫描",
    TARGET     = "目标切换",
    LOG_FWD    = "战斗日志",
    LOG_REV    = "战斗日志·反击",
    LOG_CAST   = "施法复核",
    SPECIAL    = "对话NPC",
    OPENING    = "开怪NPC",
    ENCOUNTER  = "首领开始",
}

local ATTACK_EVENTS = {
    SWING_DAMAGE            = true,
    RANGE_DAMAGE            = true,
    SPELL_DAMAGE            = true,
    SPELL_PERIODIC_DAMAGE   = true,
    DAMAGE_SHIELD           = true,
    DAMAGE_SPLIT            = true,
}

local NON_ENGAGING_SPELL_IDS = {
    [1130] = true,     -- 猎人印记
    [14323] = true,
    [14324] = true,
    [14325] = true,
    [53338] = true,
    [1284419] = true,  -- 袋里藏沙
}

local NON_ENGAGING_SPELL_NAMES = {
    ["猎人印记"] = true,
    ["袋里藏沙"] = true,
}

local function IsNonEngagingSpell(spellId, spellName)
    if NON_ENGAGING_SPELL_IDS[tonumber(spellId) or 0] then return true end
    return spellName and NON_ENGAGING_SPELL_NAMES[spellName] == true or false
end

local IGNORED_ADD_NPCS = {
    [34800] = true,  -- 雪地狗头人奴隶
    [34854] = true,  -- 火焰炸弹
    [14826] = true,  -- 妖术师金度的祭品巨魔：不是开怪单位
    [11357] = true,  -- 哈卡之子：不是开怪单位
    [33136] = true,  -- 尤格萨隆的守护者：出现较晚，不作为开怪依据
    [33966] = true,  -- 尤格萨隆阶段小怪：不作为开怪依据
    [33983] = true,  -- 尤格萨隆阶段小怪：不作为开怪依据
    [33985] = true,  -- 尤格萨隆阶段小怪：不作为开怪依据
    [33988] = true,  -- 尤格萨隆阶段小怪：不作为开怪依据
}

local PULL_EVIDENCE_ADD_NPCS = {
    [25588] = true,  -- 基尔加丹之手
}

local NPC_DAMAGE_EVENTS = {
    SWING_DAMAGE          = true,
    SWING_MISSED          = true,
    RANGE_DAMAGE          = true,
    RANGE_MISSED          = true,
    SPELL_DAMAGE          = true,
    SPELL_MISSED          = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_PERIODIC_MISSED = true,
    DAMAGE_SHIELD         = true,
    DAMAGE_SPLIT          = true,
}

local ACTION_LOOKUP_WINDOW = 1.8
local SPECIAL_TARGET_WINDOW = 60
local SCAN_INTERVAL = 0.2
local RECORDS_PER_PAGE = 50
local HISTORY_KEY = "pullHistory"
local RETENTION_SECONDS = 3 * 24 * 60 * 60

-- ============================================================
-- Boss 数据
-- ============================================================

local TOC_DIALOGUE_BOSS_NAMES = {
    ["诺森德猛兽"] = true,
    ["加拉克苏斯大王"] = true,
    ["阵营冠军"] = true,
    ["瓦格里双子"] = true,
}

local function IsTocDialogueBoss(boss)
    return type(boss) == "table" and TOC_DIALOGUE_BOSS_NAMES[boss.name] == true
end

local DIALOGUE_NPCS = {
    [34816] = {
        name = "巴雷特·拉姆瑟",
        raid = "十字军的试炼",
        label = "对话开怪",
    },
    [35909] = {
        name = "巴雷特·拉姆瑟",
        raid = "十字军的试炼",
        label = "对话开怪",
    },
    [35035] = {
        name = "巴雷特·拉姆瑟",
        raid = "十字军的试炼",
        label = "对话开怪",
    },
    [35766] = {
        name = "巴雷特·拉姆瑟",
        raid = "十字军的试炼",
        label = "对话开怪",
    },
    [35770] = {
        name = "巴雷特·拉姆瑟",
        raid = "十字军的试炼",
        label = "对话开怪",
    },
    [33210] = {
        name = "远征军指挥官",
        raid = "奥杜尔",
        label = "对话开怪",
    },
}

local ADD_NAME_OVERRIDES = {
    [25588] = "欺诈者之手",
}

local OPENING_NAME_OVERRIDES = {
    [34816] = "巴雷特·拉姆瑟",
    [35909] = "巴雷特·拉姆瑟",
    [35035] = "巴雷特·拉姆瑟",
    [35766] = "巴雷特·拉姆瑟",
    [35770] = "巴雷特·拉姆瑟",
}

local RAID_ORDER = {
    "熔火之心",
    "毒蛇神殿",
    "风暴要塞",
    "纳克萨玛斯",
    "黑曜石圣殿",
    "永恒之眼",
    "阿尔卡冯的宝库",
    "祖尔格拉布",
    "十字军的试炼",
    "祖阿曼",
    "太阳井高地",
    "奥杜尔",
}

local BOSS_LIST = {}
local BOSS_BY_ID = {}
local BOSS_BY_NAME = {}
local OPENING_BY_ID = {}

local function AddBoss(raid, name, ids, adds, openings)
    local boss = {
        name = name,
        raid = raid,
        ids = {},
        idSet = {},
        roleById = {},
        adds = {},
        openings = {},
    }

    for _, npcId in ipairs(ids or {}) do
        npcId = tonumber(npcId)
        if npcId then
            boss.ids[#boss.ids + 1] = npcId
            boss.idSet[npcId] = true
            boss.roleById[npcId] = "boss"
            BOSS_BY_ID[npcId] = boss
        end
    end

    for _, npcId in ipairs(adds or {}) do
        npcId = tonumber(npcId)
        if npcId then
            boss.adds[#boss.adds + 1] = npcId
            boss.roleById[npcId] = "add"
            BOSS_BY_ID[npcId] = boss
        end
    end

    for _, npcId in ipairs(openings or {}) do
        npcId = tonumber(npcId)
        if npcId then
            local dialogue = DIALOGUE_NPCS[npcId]
            boss.openings[#boss.openings + 1] = npcId
            boss.roleById[npcId] = dialogue and dialogue.role ~= "opening" and "dialogue" or "opening"
            BOSS_BY_ID[npcId] = boss
            OPENING_BY_ID[npcId] = {
                boss = boss,
                role = boss.roleById[npcId],
            }
        end
    end

    BOSS_BY_NAME[name] = boss
    BOSS_LIST[#BOSS_LIST + 1] = boss
    return boss
end

local function AliasBoss(alias, bossName)
    local boss = BOSS_BY_NAME[bossName]
    if boss then
        BOSS_BY_NAME[alias] = boss
    end
end

-- 熔火之心
AddBoss("熔火之心", "鲁西弗隆", { 12118 })
AddBoss("熔火之心", "玛格曼达", { 11982 })
AddBoss("熔火之心", "基赫纳斯", { 12259 }, nil, { 11661 })
AddBoss("熔火之心", "加尔", { 12057 }, nil, { 12099 })
AddBoss("熔火之心", "沙斯拉尔", { 12264 })
AddBoss("熔火之心", "迦顿男爵", { 12056 })
AddBoss("熔火之心", "萨弗隆先驱者", { 12098 }, nil, { 11662 })
AddBoss("熔火之心", "焚化者古雷曼格", { 11988 }, nil, { 11672 })
AddBoss("熔火之心", "管理者埃克索图斯", { 12018 }, nil, { 11663, 11664 })
AddBoss("熔火之心", "拉格纳罗斯", { 11502 }, nil, { 12143 })

-- 毒蛇神殿
AddBoss("毒蛇神殿", "不稳定的海度斯", { 21216 }, nil, { 22035, 22036 })
AddBoss("毒蛇神殿", "鱼斯拉", { 21217 }, nil, { 21865, 21873 })
AddBoss("毒蛇神殿", "盲眼者莱欧瑟拉斯", { 21215 }, { 21806 }, { 21857, 21875 })
AddBoss("毒蛇神殿", "深水领主卡拉瑟雷斯", { 21214, 21964, 21965, 21966 }, { 22119, 22120, 22091, 22486, 22487 })
AddBoss("毒蛇神殿", "莫洛格里·踏潮者", { 21213 }, { 21920 })
AddBoss("毒蛇神殿", "瓦丝琪", { 21212 }, { 21958, 22009, 22055, 22056, 22140 })

-- 风暴要塞
AddBoss("风暴要塞", "奥", { 19514 }, { 19551 })
AddBoss("风暴要塞", "空灵机甲", { 19516 })
AddBoss("风暴要塞", "大星术师索兰莉安", { 18805 }, { 18806, 18925 })
AddBoss("风暴要塞", "凯尔萨斯·逐日者", { 19622, 20060, 20062, 20063, 20064 }, nil,
    { 21268, 21269, 21270, 21271, 21272, 21273, 21274, 21362, 21364 })

-- 纳克萨玛斯
AddBoss("纳克萨玛斯", "阿努布雷坎", { 15956 }, { 16573 }, { 16698 })
AddBoss("纳克萨玛斯", "黑女巫法琳娜", { 15953 }, nil, { 16505, 16506 })
AddBoss("纳克萨玛斯", "迈克斯纳", { 15952 }, { 17055, 16486 })
AddBoss("纳克萨玛斯", "瘟疫使者诺斯", { 15954 }, { 16981, 16983, 16984 })
AddBoss("纳克萨玛斯", "肮脏的希尔盖", { 15936 })
AddBoss("纳克萨玛斯", "洛欧塞布", { 16011 }, { 16286 })
AddBoss("纳克萨玛斯", "帕奇维克", { 16028 })
AddBoss("纳克萨玛斯", "格罗布鲁斯", { 15931 }, { 16290 })
AddBoss("纳克萨玛斯", "格拉斯", { 15932 }, { 16360 })
AddBoss("纳克萨玛斯", "塔迪乌斯", { 15928, 15929, 15930 })
AddBoss("纳克萨玛斯", "教官拉苏维奥斯", { 16061 }, { 16803 })
AddBoss("纳克萨玛斯", "收割者戈提克", { 16060 }, { 16124, 16125, 16126, 16127, 16148, 16149, 16150 })
AddBoss("纳克萨玛斯", "天启四骑士", { 16063, 16065, 30549, 16064 })
AddBoss("纳克萨玛斯", "萨菲隆", { 15989 })
AddBoss("纳克萨玛斯", "克尔苏加德", { 15990 }, { 16427, 23561, 16428, 23562, 16429, 16441 })

-- 黑曜石圣殿、永恒之眼
AddBoss("黑曜石圣殿", "萨塔里奥", { 28860 }, { 30449, 30451, 30452, 30643, 30890, 31218 })
AddBoss("永恒之眼", "玛里苟斯", { 28859 }, { 30084, 30245, 30249 })

-- 阿尔卡冯的宝库
AddBoss("阿尔卡冯的宝库", "岩石看守者阿尔卡冯", { 31125 })
AddBoss("阿尔卡冯的宝库", "风暴看守者埃玛尔隆", { 33993 })
AddBoss("阿尔卡冯的宝库", "烈焰看守者科拉隆", { 35013 })
AddBoss("阿尔卡冯的宝库", "寒冰看守者图拉旺", { 38433 }, { 38456 })

-- 祖尔格拉布
AddBoss("祖尔格拉布", "高阶祭司耶克里克", { 14517 })
AddBoss("祖尔格拉布", "高阶祭司温诺希斯", { 14507 }, nil, { 11373 })
AddBoss("祖尔格拉布", "高阶祭司玛尔里", { 14510 }, nil, { 15041 })
AddBoss("祖尔格拉布", "血领主曼多基尔", { 11382 }, { 14988 })
AddBoss("祖尔格拉布", "疯狂之缘", { 15082, 15083, 15084, 15085 }, nil, { 15163 })
AddBoss("祖尔格拉布", "高阶祭司塞卡尔", { 14509, 11347, 11348 }, nil, { 166359 })
AddBoss("祖尔格拉布", "加兹兰卡", { 15114 })
AddBoss("祖尔格拉布", "高阶祭司娅尔罗", { 14515 }, nil, { 15101 })
AddBoss("祖尔格拉布", "妖术师金度", { 11380 }, nil, { 14987, 15112, 14986 })
AddBoss("祖尔格拉布", "哈卡", { 14834 })

-- 十字军的试炼
AddBoss("十字军的试炼", "诺森德猛兽", { 34796, 35144, 34799, 34797 }, { 34800 }, { 34816, 35909 })
AddBoss("十字军的试炼", "加拉克苏斯大王", { 34780 }, { 34826, 34815, 34813, 34825 }, { 35035 })
AddBoss("十字军的试炼", "阵营冠军", {
    34461, 34460, 34469, 34467, 34468, 34465, 34471, 34466, 34473, 34472, 34470,
    34463, 34474, 34475, 34458, 34451, 34459, 34448, 34449, 34445, 34456, 34447,
    34441, 34454, 34444, 34455, 34450, 34453,
}, { 35610, 35465, 34686, 34687 }, { 5925, 6112, 36070, 35766 })
AddBoss("十字军的试炼", "瓦格里双子", { 34497, 34496 }, nil, { 35770 })
AddBoss("十字军的试炼", "阿努巴拉克", { 34564 }, { 34607, 34605, 34606 })

-- 祖阿曼
AddBoss("祖阿曼", "埃基尔松", { 23574 }, { 24858 })
AddBoss("祖阿曼", "纳洛拉克", { 23576 })
AddBoss("祖阿曼", "加亚莱", { 23578 }, { 23598, 23818, 24504 })
AddBoss("祖阿曼", "哈尔拉兹", { 23577, 24144 }, { 24143, 24224 })
AddBoss("祖阿曼", "妖术领主玛拉卡斯", { 24239 }, nil, { 24240, 24241, 24242, 24243, 24244, 24245, 24246, 24247 })
AddBoss("祖阿曼", "祖尔金", { 23863 }, { 24338, 24320 }, { 23889 })

-- 太阳井高地
AddBoss("太阳井高地", "卡雷苟斯", { 24850, 24892 })
AddBoss("太阳井高地", "布鲁塔卢斯", { 24882 })
AddBoss("太阳井高地", "菲米丝", { 25038 }, { 25268 })
AddBoss("太阳井高地", "艾瑞达双子", { 25165, 25166 }, { 25214 })
AddBoss("太阳井高地", "穆鲁", { 25741, 25840 }, { 25744, 25772, 25798, 25799, 25824 })
AddBoss("太阳井高地", "基尔加丹", { 25315 }, { 25588, 25598, 25502, 25708 }, { 25955 })

-- 奥杜尔
AddBoss("奥杜尔", "烈焰巨兽", { 33113 }, { 33139 })
AddBoss("奥杜尔", "掌炉者伊格尼斯", { 33118 }, { 33121 })
AddBoss("奥杜尔", "锋鳞", { 33186 }, { 33388, 33453, 33846 }, { 33210 })
AddBoss("奥杜尔", "XT-002拆解者", { 33293 }, {
    33329, 34004, 33343, 33344, 33346, 34267, 34269, 34271, 34273, 34288,
})
AddBoss("奥杜尔", "钢铁议会", { 32857, 32867, 32927 })
AddBoss("奥杜尔", "科隆加恩", { 32930, 32933, 32934 }, { 33768 })
AddBoss("奥杜尔", "欧尔莉亚", { 33515 }, { 34014, 34034, 34035 })
AddBoss("奥杜尔", "霍迪尔", { 32845 }, { 32926, 32938 })
AddBoss("奥杜尔", "托里姆", { 32865 }, { 33196, 32883, 32907, 32882 }, { 32876, 32877, 32878, 33125 })
AddBoss("奥杜尔", "弗蕾亚", { 32906 }, { 32913, 32914, 32915, 32916, 32918, 32919, 33168 })
AddBoss("奥杜尔", "米米尔隆", { 33350, 33432, 33651, 33670 }, { 33836, 33855, 34057, 34071, 34147 })
AddBoss("奥杜尔", "维扎克斯将军", { 33271 }, { 33524, 33488 })
AddBoss("奥杜尔", "尤格-萨隆", { 33288, 33890 }, { 33136, 33966, 33983, 33985, 33988 })
AddBoss("奥杜尔", "观察者奥尔加隆", { 32871 }, { 32955, 33052, 33089, 34097 })

AliasBoss("药剂师诺斯", "瘟疫使者诺斯")
AliasBoss("迈顿男爵", "迦顿男爵")
AliasBoss("尤格萨隆", "尤格-萨隆")
AliasBoss("穿刺者戈莫克", "诺森德猛兽")
AliasBoss("酸喉", "诺森德猛兽")
AliasBoss("恐鳞", "诺森德猛兽")
AliasBoss("冰吼", "诺森德猛兽")
AliasBoss("光明邪使菲奥拉", "瓦格里双子")
AliasBoss("黑暗邪使艾蒂丝", "瓦格里双子")

local function NpcIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    if type(strsplit) == "function" then
        local value = select(6, strsplit("-", guid))
        local npcId = tonumber(value)
        if npcId then return npcId end
    end
    local npcId = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if npcId then return tonumber(npcId) end
    return nil
end

local function GetPullInfo(guid, name)
    local npcId = NpcIDFromGUID(guid)
    local boss = npcId and BOSS_BY_ID[npcId]
    local role = boss and npcId and boss.roleById[npcId]

    if not boss and name then
        boss = BOSS_BY_NAME[name]
    end
    if boss and not role then
        role = "boss"
    end
    local dialogue = npcId and DIALOGUE_NPCS[npcId]
    if dialogue then
        role = dialogue.role or "dialogue"
    end
    return boss, role, npcId
end

local function GetOrCreateEncounterBoss(encounterName)
    if not encounterName or encounterName == "" then return nil end
    local boss = BOSS_BY_NAME[encounterName]
    if boss then return boss end

    local zoneName = GetRealZoneText and GetRealZoneText() or "未知区域"
    boss = {
        name = encounterName,
        raid = zoneName,
        ids = {},
        idSet = {},
        roleById = {},
        adds = {},
        openings = {},
        dynamic = true,
    }
    BOSS_BY_NAME[encounterName] = boss
    BOSS_LIST[#BOSS_LIST + 1] = boss
    return boss
end

local function RegisterEncounterBoss(encounterName)
    local boss = GetOrCreateEncounterBoss(encounterName)
    if not boss then return nil end

    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) and not UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            local npcId = NpcIDFromGUID(guid)
            if npcId then
                if not BOSS_BY_ID[npcId] or BOSS_BY_ID[npcId].dynamic then
                    BOSS_BY_ID[npcId] = boss
                end
                if not boss.idSet[npcId] then
                    boss.ids[#boss.ids + 1] = npcId
                    boss.idSet[npcId] = true
                end
                boss.roleById[npcId] = "boss"
            end
            local unitName = UnitName(unit)
            if unitName and not BOSS_BY_NAME[unitName] then
                BOSS_BY_NAME[unitName] = boss
            end
        end
    end
    return boss
end

-- ============================================================
-- 设置与状态
-- ============================================================

local DEFAULT_SOUND_KIT = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN)
    or (SOUNDKIT and SOUNDKIT.RAID_WARNING)
    or 8960

local DEFAULT_TEMPLATE_LEAD = "[首拉] "
local DEFAULT_TEMPLATE = DEFAULT_TEMPLATE_LEAD .. "{puller} {type} {mob}{distance}"
local DEFAULT_TEMPLATE_TOKENS = { "puller", "type", "mob", "distance" }
local TEMPLATE_TOKEN_DEFS = {
    { key = "puller", label = "开怪者" },
    { key = "npc", label = "对话人" },
    { key = "mob", label = "开怪目标" },
    { key = "type", label = "动作" },
    { key = "distance", label = "距离" },
    { key = "boss", label = "所属首领" },
    { key = "raid", label = "副本" },
    { key = "time", label = "时间" },
    { key = "source", label = "检测来源" },
    { key = "npcid", label = "NPC ID" },
    { key = "count", label = "团队人数" },
}
local TEMPLATE_TOKEN_ALIASES = {
    dialogue = "npc",
}
local TEMPLATE_TOKEN_LABELS = {}
local TEMPLATE_TOKEN_SET = {}
for _, definition in ipairs(TEMPLATE_TOKEN_DEFS) do
    TEMPLATE_TOKEN_LABELS[definition.key] = definition.label
    TEMPLATE_TOKEN_SET[definition.key] = true
end

local function NormalizeTemplateTokens(tokens)
    local result = {}
    local seen = {}
    if type(tokens) ~= "table" then return result end
    for _, key in ipairs(tokens) do
        key = TEMPLATE_TOKEN_ALIASES[key] or key
        if TEMPLATE_TOKEN_SET[key] and not seen[key] then
            seen[key] = true
            result[#result + 1] = key
        end
    end
    return result
end

local function ParseTemplateDefinition(template)
    template = type(template) == "string" and template or ""
    local tokens = {}
    local separators = {}
    local seen = {}
    local firstStart
    local lastEnd
    local previousTokenEnd
    local searchAt = 1

    while true do
        local tokenStart, tokenEnd = template:find("{%w+}", searchAt)
        if not tokenStart then break end
        local key = template:sub(tokenStart + 1, tokenEnd - 1)
        key = TEMPLATE_TOKEN_ALIASES[key] or key
        if TEMPLATE_TOKEN_SET[key] then
            if not seen[key] then
                seen[key] = true
                tokens[#tokens + 1] = key
                separators[#tokens] = previousTokenEnd
                    and template:sub(previousTokenEnd + 1, tokenStart - 1) or ""
                firstStart = firstStart or tokenStart
            end
            lastEnd = tokenEnd
            previousTokenEnd = tokenEnd
        end
        searchAt = tokenEnd + 1
    end

    local lead = firstStart and template:sub(1, firstStart - 1) or template
    local suffix = lastEnd and template:sub(lastEnd + 1) or ""
    return tokens, lead, suffix, separators
end

local function BuildTemplateFromTokens(tokens, lead, suffix, separators)
    tokens = NormalizeTemplateTokens(tokens)
    lead = type(lead) == "string" and lead or ""
    suffix = type(suffix) == "string" and suffix or ""

    local output = lead
    local previousKey
    for index, key in ipairs(tokens) do
        local token = "{" .. key .. "}"
        if index == 1 then
            output = output .. token
        else
            local separator = type(separators) == "table" and separators[index] or nil
            if type(separator) ~= "string" then
                separator = (key == "distance" and previousKey == "mob") and "" or " "
            end
            output = output .. separator .. token
        end
        previousKey = key
    end
    return output .. suffix
end

local function CopyTemplateTokens(tokens)
    local result = {}
    for _, key in ipairs(tokens or DEFAULT_TEMPLATE_TOKENS) do
        result[#result + 1] = key
    end
    return result
end

local function CopyTemplateSeparators(separators)
    if type(separators) ~= "table" then return nil end
    local result = {}
    for index = 1, #separators do result[index] = separators[index] end
    return result
end

local settings = {
    reportMode = "boss",
    template = DEFAULT_TEMPLATE,
    templateLead = DEFAULT_TEMPLATE_LEAD,
    templateSuffix = "",
    templateTokens = CopyTemplateTokens(DEFAULT_TEMPLATE_TOKENS),
    templateSeparators = { "", " ", " ", "" },
    delayOutOfCombat = false,
    delaySeconds = 3,
    textEnabled = true,
    soundEnabled = true,
    soundKit = DEFAULT_SOUND_KIT,
    popupEnabled = true,
    includeDistance = true,
    selectedTab = 1,
}

local pullLog = {}
local selectedRecord
local nextPullID = 1
local reportedMobs = {}
local deadMobs = {}
local petOwnerMap = {}
local summonMap = {}
local dynamicAddBoss = {}
local groupUnits = {}
local groupGUIDs = {}
local groupNameByGUID = {}
local groupNameSet = {}
local lastUnitByGUID = {}
local lastTargets = {}
local recentCastByDest = {}
local specialCandidates = {}
local lastSpecialTargetByUnit = {}
local npcInteractions = {}
local lastFriendlyNpcTargetByUnit = {}
local reportedEncounterBosses = {}
local pendingCasts = {}
local pendingAnnouncements = {
    items = {},
    readyAt = 0,
    nextSendAt = 0,
    waitingCombat = false,
}
local activeEncounter
local activeBossGUID
local bossReported = false
local bossEngagedAt
local initialAddReports = 0
local dialogueFallbackGeneration = 0
local combatStartedAt
local firstPullReported = false
local lastZoneName
local scanTicker
local historyTicker
local scanScheduled = false
local scanRound = 0
local resetGeneration = 0
local debugEnabled = false
local nextHistoryPruneAt = 0
local suppressCurrentCombat = false

local settingsStatus
local listFrame
local delayEdit
local reportModeLabels
local modeButton
local SetReportMode
local SyncTemplateBuilderUI
local OpenTemplateEditor
local settingsControlsReady = false
local selectedTab = 1
local recordRows = {}
local lastPopupRecord
local currentRecordPage = 1

local RefreshRecordList
local RefreshBossList
local SyncSettingsUI
local SelectTab
local SelectRecord
local ShowRecordDetail
local UpdateRecordSelection
local ClearRecords
local UpdateWindowPosition

local function DebugPrint(message)
    if debugEnabled then
        print("|cff66ccff[WhoAdd]|r " .. tostring(message))
    end
end

local function After(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
    else
        callback()
    end
end

local function SetSolidColor(texture, r, g, b, a)
    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a)
    else
        texture:SetTexture(r, g, b, a)
    end
end

local function CopyTable(source)
    if type(source) ~= "table" then return source end
    local result = {}
    for key, value in pairs(source) do
        result[key] = CopyTable(value)
    end
    return result
end

local function SanitizeStoredRecord(record)
    if type(record) ~= "table" then return nil end
    record.boss = nil
    record.id = tonumber(record.id) or 0
    record.epoch = tonumber(record.epoch)
    record.snapshot = type(record.snapshot) == "table" and record.snapshot or {
        players = {},
        mob = {},
    }
    if type(record.snapshot.players) ~= "table" then record.snapshot.players = {} end
    if type(record.snapshot.mob) ~= "table" then record.snapshot.mob = {} end
    if type(record.encounter) ~= "table" then record.encounter = nil end
    return record
end

local function SaveHistory()
    if type(WhoAddDB) ~= "table" then return end
    WhoAddDB[HISTORY_KEY] = pullLog
end

local function LoadHistory()
    pullLog = {}
    if type(WhoAddDB) ~= "table" or type(WhoAddDB[HISTORY_KEY]) ~= "table" then
        nextPullID = 1
        return
    end

    local now = time()
    local maxId = 0
    for _, stored in ipairs(WhoAddDB[HISTORY_KEY]) do
        local record = SanitizeStoredRecord(stored)
        if record then
            record.epoch = record.epoch or now
            if now - record.epoch <= RETENTION_SECONDS then
                if record.id <= 0 then
                    record.id = maxId + 1
                end
                maxId = math.max(maxId, record.id)
                pullLog[#pullLog + 1] = record
            end
        end
    end

    table.sort(pullLog, function(left, right)
        if left.id == right.id then
            return (left.epoch or 0) > (right.epoch or 0)
        end
        return left.id > right.id
    end)
    nextPullID = math.max(1, maxId + 1)
    SaveHistory()
end

local function PersistToDisk()
    if type(WhoAddDB) == "table" then
        WhoAddDB.savedAt = time()
    end
    if C_AddOns and type(C_AddOns.SaveAddOns) == "function" then
        pcall(C_AddOns.SaveAddOns)
    elseif type(SaveVariables) == "function" then
        pcall(SaveVariables, "WhoAddDB")
    end
end

local function PruneExpiredHistory()
    local now = time()
    local changed = false

    for index = #pullLog, 1, -1 do
        local record = pullLog[index]
        local epoch = record and tonumber(record.epoch)
        if not epoch or now - epoch > RETENTION_SECONDS then
            local removed = table.remove(pullLog, index)
            changed = true
            if selectedRecord == removed then selectedRecord = nil end
        end
    end

    if not changed then return 0 end
    SaveHistory()
    PersistToDisk()
    if listFrame and listFrame:IsShown() and selectedTab == 1 and RefreshRecordList then
        RefreshRecordList()
    end
    return 1
end

local function StartHistoryMaintenance()
    if historyTicker or not C_Timer or not C_Timer.NewTicker then return end
    historyTicker = C_Timer.NewTicker(300, function()
        PruneExpiredHistory()
    end)
end

local function LoadSettings()
    if type(WhoAddDB) ~= "table" then WhoAddDB = {} end
    local oldSchema = tonumber(WhoAddDB.schema) or 0

    local reportMode = WhoAddDB.reportMode
    if reportMode ~= "all" and reportMode ~= "boss" and reportMode ~= "none" then
        reportMode = "boss"
    end
    settings.reportMode = reportMode

    local storedTemplate = type(WhoAddDB.template) == "string" and WhoAddDB.template or ""
    if storedTemplate == "" then storedTemplate = DEFAULT_TEMPLATE end
    local parsedTokens, parsedLead, parsedSuffix, parsedSeparators =
        ParseTemplateDefinition(storedTemplate)
    if type(WhoAddDB.templateTokens) == "table" then
        settings.templateTokens = NormalizeTemplateTokens(WhoAddDB.templateTokens)
    else
        settings.templateTokens = parsedTokens
    end
    settings.templateLead = type(WhoAddDB.templateLead) == "string"
        and WhoAddDB.templateLead or parsedLead
    settings.templateSuffix = type(WhoAddDB.templateSuffix) == "string"
        and WhoAddDB.templateSuffix or parsedSuffix
    if type(WhoAddDB.templateSeparators) == "table" then
        settings.templateSeparators = CopyTemplateSeparators(WhoAddDB.templateSeparators)
    elseif type(WhoAddDB.templateTokens) ~= "table" then
        settings.templateSeparators = CopyTemplateSeparators(parsedSeparators)
    else
        settings.templateSeparators = nil
    end
    settings.template = BuildTemplateFromTokens(settings.templateTokens,
        settings.templateLead, settings.templateSuffix, settings.templateSeparators)

    settings.delayOutOfCombat = WhoAddDB.delayOutOfCombat == true
    settings.delaySeconds = math.max(1, math.min(30, tonumber(WhoAddDB.delaySeconds) or 3))
    settings.textEnabled = oldSchema < 3 and true or WhoAddDB.textEnabled ~= false
    settings.soundEnabled = WhoAddDB.soundEnabled ~= false
    settings.soundKit = tonumber(WhoAddDB.soundKit) or DEFAULT_SOUND_KIT
    settings.popupEnabled = oldSchema < 3 and true or WhoAddDB.popupEnabled ~= false
    settings.includeDistance = WhoAddDB.includeDistance ~= false
    local minimapDB = type(WhoAddDB.minimap) == "table" and WhoAddDB.minimap or {}
    if minimapDB.minimapPos == nil then
        minimapDB.minimapPos = tonumber(WhoAddDB.minimapAngle) or 225
    end
    if minimapDB.hide == nil then minimapDB.hide = false end
    WhoAddDB.minimap = minimapDB
    WhoAddDB.minimapAngle = nil
    settings.selectedTab = math.max(1, math.min(3, tonumber(WhoAddDB.selectedTab) or 1))
    selectedTab = settings.selectedTab
    debugEnabled = WhoAddDB.debug == true
end

local function SaveSettings(silent)
    if type(WhoAddDB) ~= "table" then WhoAddDB = {} end
    if settingsControlsReady and delayEdit then
        settings.delaySeconds = math.max(1, math.min(30, tonumber(delayEdit:GetText()) or settings.delaySeconds or 3))
    end
    settings.templateTokens = NormalizeTemplateTokens(settings.templateTokens)
    settings.template = BuildTemplateFromTokens(settings.templateTokens,
        settings.templateLead, settings.templateSuffix, settings.templateSeparators)
    WhoAddDB.schema = 5
    WhoAddDB.reportMode = settings.reportMode
    WhoAddDB.template = settings.template
    WhoAddDB.templateLead = settings.templateLead
    WhoAddDB.templateSuffix = settings.templateSuffix
    WhoAddDB.templateTokens = CopyTemplateTokens(settings.templateTokens)
    WhoAddDB.templateSeparators = CopyTemplateSeparators(settings.templateSeparators)
    WhoAddDB.delayOutOfCombat = settings.delayOutOfCombat and true or false
    WhoAddDB.delaySeconds = tonumber(settings.delaySeconds) or 3
    WhoAddDB.textEnabled = settings.textEnabled and true or false
    WhoAddDB.soundEnabled = settings.soundEnabled and true or false
    WhoAddDB.soundKit = tonumber(settings.soundKit) or DEFAULT_SOUND_KIT
    WhoAddDB.soundFile = nil
    WhoAddDB.popupEnabled = settings.popupEnabled and true or false
    WhoAddDB.includeDistance = settings.includeDistance and true or false
    WhoAddDB.selectedTab = selectedTab
    WhoAddDB.debug = debugEnabled and true or false

    PersistToDisk()
    if not silent and settingsStatus then
        settingsStatus:SetText("|cff4caf50设置已保存|r  |cff9eacbb" .. date("%H:%M:%S") .. "|r")
    end
end

local function InitDatabase()
    LoadSettings()
    LoadHistory()
    StartHistoryMaintenance()
    if SyncSettingsUI then SyncSettingsUI() end
    settingsControlsReady = true
    SaveSettings(true)
    if UpdateWindowPosition then UpdateWindowPosition() end
    if WhoAdd.SetupMinimapIcon then WhoAdd.SetupMinimapIcon() end
end

-- ============================================================
-- 通用工具
-- ============================================================

local function TrimMessage(message)
    message = tostring(message or "")
    if #message > 250 then
        message = message:sub(1, 247) .. "..."
    end
    return message
end

local function IsGroupType()
    if IsInRaid() then return true end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return true end
    return IsInGroup() and true or false
end

local function BuildRosterCache()
    groupUnits = {}
    groupGUIDs = {}
    groupNameByGUID = {}
    groupNameSet = {}

    local function AddUnit(unit)
        if not UnitExists(unit) then return end
        local name = UnitName(unit)
        local guid = UnitGUID(unit)
        if name then
            groupUnits[#groupUnits + 1] = unit
            groupNameSet[name] = true
            if guid then
                groupGUIDs[guid] = true
                groupNameByGUID[guid] = name
            end
        end
    end

    if IsInRaid() then
        for i = 1, 40 do AddUnit("raid" .. i) end
    elseif IsInGroup() then
        AddUnit("player")
        for i = 1, 4 do AddUnit("party" .. i) end
    else
        AddUnit("player")
    end
end

local function BuildPetMap()
    petOwnerMap = {}

    local function AddPet(ownerToken, petToken)
        local petGUID = UnitGUID(petToken)
        local ownerName = UnitName(ownerToken)
        if petGUID and ownerName then
            petOwnerMap[petGUID] = ownerName
        end
    end

    AddPet("player", "pet")
    if IsInRaid() then
        for i = 1, 40 do
            AddPet("raid" .. i, "raidpet" .. i)
            AddPet("raid" .. i, "raid" .. i .. "pet")
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            AddPet("party" .. i, "partypet" .. i)
        end
    end
end

local function IsGroupGUID(guid)
    if not guid then return false end
    return groupGUIDs[guid] == true
        or petOwnerMap[guid] ~= nil
        or summonMap[guid] ~= nil
end

local function IsGroupActor(guid, name, flags)
    if flags and bit.band(flags, AFFILIATION_GROUP_MASK) > 0 then return true end
    if IsGroupGUID(guid) then return true end
    return name and groupNameSet[name] == true
end

local function IsGroupUnit(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsUnit(unit, "player") or UnitIsUnit(unit, "pet") then return true end
    if UnitPlayerOrPetInRaid and UnitPlayerOrPetInRaid(unit) then return true end
    if UnitPlayerOrPetInParty and UnitPlayerOrPetInParty(unit) then return true end
    return IsGroupGUID(UnitGUID(unit))
end

local function IsGroupTargetUnit(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsUnit(unit, "player") or UnitIsUnit(unit, "pet") then return true end
    if UnitPlayerOrPetInRaid and UnitPlayerOrPetInRaid(unit) then return true end
    if UnitPlayerOrPetInParty and UnitPlayerOrPetInParty(unit) then return true end
    return IsGroupGUID(UnitGUID(unit))
end

local function UnitTargetToken(unit)
    if unit == "player" then return "target" end
    if unit == "pet" then return "pettarget" end
    if not unit then return nil end
    return unit .. "target"
end

local function ResolveOwner(unit)
    if not unit or not UnitExists(unit) then return nil, nil end
    local guid = UnitGUID(unit)
    if UnitIsPlayer(unit) then
        return UnitName(unit), guid
    end
    if guid and petOwnerMap[guid] then
        for ownerGUID, ownerName in pairs(groupNameByGUID) do
            if ownerName == petOwnerMap[guid] then
                return ownerName, ownerGUID
            end
        end
        return petOwnerMap[guid], nil
    end
    if guid and summonMap[guid] then
        for ownerGUID, ownerName in pairs(groupNameByGUID) do
            if ownerName == summonMap[guid] then
                return ownerName, ownerGUID
            end
        end
        return summonMap[guid], nil
    end
    return UnitName(unit), guid
end

local function ResolveOwnerByGUID(guid, fallbackName)
    if guid and groupNameByGUID[guid] then return groupNameByGUID[guid], guid end
    local ownerName = guid and (petOwnerMap[guid] or summonMap[guid])
    if ownerName then
        for ownerGUID, name in pairs(groupNameByGUID) do
            if name == ownerName then return ownerName, ownerGUID end
        end
        return ownerName, nil
    end
    return fallbackName, guid
end

local function IsNpcInteractionTarget(targetUnit)
    if not targetUnit or not UnitExists(targetUnit) then return false end
    if UnitIsPlayer(targetUnit) then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(targetUnit) then return false end
    local guid = UnitGUID(targetUnit)
    local npcId = guid and NpcIDFromGUID(guid)
    return npcId ~= nil and DIALOGUE_NPCS[npcId] ~= nil
end

local function TrackNpcInteraction(unit, forceClick)
    if not unit or not UnitExists(unit) then return end
    local targetUnit = UnitTargetToken(unit)
    if not IsNpcInteractionTarget(targetUnit) then
        lastFriendlyNpcTargetByUnit[unit] = nil
        return
    end

    local targetGUID = UnitGUID(targetUnit)
    local targetName = UnitName(targetUnit) or "未知NPC"
    local ownerName, ownerGUID
    if UnitIsPlayer(unit) then
        ownerName = UnitName(unit)
        ownerGUID = UnitGUID(unit)
    else
        ownerName, ownerGUID = ResolveOwnerByGUID(UnitGUID(unit), UnitName(unit))
    end
    if not ownerName then return end

    local key = ownerGUID or ownerName
    local previousTarget = lastFriendlyNpcTargetByUnit[unit]
    local entry = npcInteractions[key]
    if not entry and previousTarget == targetGUID and not forceClick then
        return
    end

    local now = GetTime()
    if not entry then
        entry = {
            name = ownerName,
            guid = ownerGUID,
            firstAt = now,
            firstClock = date("%H:%M:%S"),
            lastSeenAt = now,
            clicks = 0,
            npcs = {},
        }
        npcInteractions[key] = entry
    end

    entry.lastSeenAt = now
    if forceClick or previousTarget ~= targetGUID then
        entry.clicks = entry.clicks + 1
        entry.lastClickAt = now
        entry.lastClickClock = date("%H:%M:%S")
    end
    local npc = entry.npcs[targetGUID]
    if not npc then
        npc = { name = targetName, firstAt = now, lastSeenAt = now }
        entry.npcs[targetGUID] = npc
    else
        npc.lastSeenAt = now
    end
    lastFriendlyNpcTargetByUnit[unit] = targetGUID
end

local function CleanupNpcInteractions(now)
    now = now or GetTime()
    for key, entry in pairs(npcInteractions) do
        if now - entry.lastSeenAt > 600 then
            npcInteractions[key] = nil
        end
    end
end

local function GetNpcInteractionSummary(expectedEncounterName)
    CleanupNpcInteractions()
    local expectedBoss = expectedEncounterName and BOSS_BY_NAME[expectedEncounterName] or nil
    local expectedRaid = expectedBoss and expectedBoss.raid or nil
    local rows = {}
    for _, entry in pairs(npcInteractions) do
        local interactionRole
        local interactionNpcGUID
        local interactionNpcName
        if expectedEncounterName then
            for npcGUID, npc in pairs(entry.npcs or {}) do
                local npcId = NpcIDFromGUID(npcGUID)
                local dialogue = npcId and DIALOGUE_NPCS[npcId] or nil
                local opening = npcId and OPENING_BY_ID[npcId] or nil
                local mappedBoss = opening and opening.boss or nil
                if dialogue and mappedBoss and (
                    mappedBoss == expectedBoss
                    or (dialogue.raidWide and expectedRaid and mappedBoss.raid == expectedRaid)
                ) then
                    interactionRole = dialogue.role or "dialogue"
                    interactionNpcGUID = npcGUID
                    interactionNpcName = dialogue.name or npc.name
                    break
                end
            end
        else
            interactionRole = "dialogue"
        end

        if not expectedEncounterName or interactionRole then
            rows[#rows + 1] = {
                name = entry.name,
                guid = entry.guid,
                firstAt = entry.firstAt,
                firstClock = entry.firstClock,
                lastClickAt = entry.lastClickAt,
                lastClickClock = entry.lastClickClock,
                lastSeenAt = entry.lastSeenAt,
                clicks = entry.clicks,
                duration = math.max(0, entry.lastSeenAt - entry.firstAt),
                interactionRole = interactionRole,
                npcGUID = interactionNpcGUID,
                npcName = interactionNpcName,
            }
        end
    end
    table.sort(rows, function(left, right)
        if left.firstAt == right.firstAt then
            return (left.guid or left.name) < (right.guid or right.name)
        end
        return left.firstAt < right.firstAt
    end)

    local fullParts = {}
    local chatParts = {}
    for index, row in ipairs(rows) do
        row.order = index
        local duration = row.duration >= 1 and string.format("%.1f秒", row.duration) or "<1秒"
        local firstClock = row.firstClock or "时间未知"
        local lastClick = ""
        if row.lastClickClock and row.lastClickClock ~= firstClock then
            lastClick = "，最后点击" .. row.lastClickClock
        end
        fullParts[#fullParts + 1] = string.format("%d.%s（首次点击%s，点击%d次%s，持续%s）",
            index, row.name or "未知", firstClock, row.clicks or 0, lastClick, duration)
        local chatPart = string.format("%d.%s@%s/%s", index, row.name or "未知", firstClock, duration)
        local candidate = table.concat(chatParts, "、") .. (index > 1 and "、" or "") .. chatPart
        if #candidate > 160 then
            chatParts[#chatParts + 1] = string.format("等%d人", #rows - index + 1)
            break
        end
        chatParts[#chatParts + 1] = chatPart
    end

    return rows, table.concat(fullParts, "\n"), table.concat(chatParts, "、")
end

local function ClearNpcInteractions()
    npcInteractions = {}
end

local function AnyoneInCombat()
    if UnitAffectingCombat("player") then return true end
    for _, unit in ipairs(groupUnits) do
        if UnitAffectingCombat(unit) then return true end
    end
    return false
end

local function IsHostileUnit(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitCanAttack and UnitCanAttack("player", unit) then return true end
    if UnitIsFriend and UnitIsFriend("player", unit) then return false end
    local reaction = UnitReaction and UnitReaction("player", unit)
    return reaction and reaction <= 4 and true or false
end

local function FindUnitForGUID(guid)
    if not guid then return nil end

    local cached = lastUnitByGUID[guid]
    if cached and UnitExists(cached) and UnitGUID(cached) == guid then
        return cached
    end

    local fixed = { "target", "focus", "mouseover", "targettarget" }
    for _, unit in ipairs(fixed) do
        if UnitExists(unit) and UnitGUID(unit) == guid then
            lastUnitByGUID[guid] = unit
            return unit
        end
    end

    for i = 1, 5 do
        local unit = "boss" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            lastUnitByGUID[guid] = unit
            return unit
        end
    end

    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            lastUnitByGUID[guid] = unit
            return unit
        end
    end

    for _, unit in ipairs(groupUnits) do
        local targetUnit = UnitTargetToken(unit)
        if UnitExists(targetUnit) and UnitGUID(targetUnit) == guid then
            lastUnitByGUID[guid] = targetUnit
            return targetUnit
        end
    end

    return nil
end

local function DistanceBetweenUnits(unitA, unitB)
    if not unitA or not unitB or not UnitExists(unitA) or not UnitExists(unitB) then
        return nil
    end

    local x1, y1, _, map1 = UnitPosition(unitA)
    local x2, y2, _, map2 = UnitPosition(unitB)
    if x1 and y1 and x2 and y2 and (not map1 or not map2 or map1 == map2) then
        local dx = x1 - x2
        local dy = y1 - y2
        return math.sqrt(dx * dx + dy * dy)
    end

    if UnitIsUnit(unitA, "player") and type(UnitDistanceSquared) == "function" then
        local ok, squared, valid = pcall(UnitDistanceSquared, unitB)
        if ok and type(squared) == "number" and squared >= 0 and valid ~= false then
            return math.sqrt(squared)
        end
    end
    return nil
end

local function ReadCast(unit)
    local cast
    local ok, name, _, _, startMS, endMS, _, _, notInterruptible = pcall(UnitCastingInfo, unit)
    if ok and name then
        local nowMS = GetTime() * 1000
        cast = {
            name = name,
            kind = "施法",
            remaining = math.max(0, ((tonumber(endMS) or nowMS) - nowMS) / 1000),
            duration = math.max(0, ((tonumber(endMS) or nowMS) - (tonumber(startMS) or nowMS)) / 1000),
            notInterruptible = notInterruptible and true or false,
        }
    end

    if not cast then
        ok, name, _, _, startMS, endMS, _, notInterruptible = pcall(UnitChannelInfo, unit)
        if ok and name then
            local nowMS = GetTime() * 1000
            cast = {
                name = name,
                kind = "引导",
                remaining = math.max(0, ((tonumber(endMS) or nowMS) - nowMS) / 1000),
                duration = math.max(0, ((tonumber(endMS) or nowMS) - (tonumber(startMS) or nowMS)) / 1000),
                notInterruptible = notInterruptible and true or false,
            }
        end
    end
    return cast
end

local function ClassColor(classFile)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not color then return "|cffffffff" end
    return string.format("|cff%02x%02x%02x",
        math.floor((color.r or 1) * 255),
        math.floor((color.g or 1) * 255),
        math.floor((color.b or 1) * 255))
end

local function SnapshotPlayer(unit, mobUnit)
    local name = UnitName(unit)
    local guid = UnitGUID(unit)
    local classFile, classLocal = UnitClass(unit)
    local role = "NONE"
    if UnitGroupRolesAssigned then
        local ok, value = pcall(UnitGroupRolesAssigned, unit)
        if ok and value then role = value end
    end

    local health, healthMax = 0, 0
    if UnitHealth and UnitHealthMax then
        health = tonumber(UnitHealth(unit)) or 0
        healthMax = tonumber(UnitHealthMax(unit)) or 0
    end
    local healthPct = healthMax > 0 and (health / healthMax * 100) or 0

    local targetName, targetGUID, targetType
    local targetUnit = UnitTargetToken(unit)
    if UnitExists(targetUnit) then
        targetName = UnitName(targetUnit)
        targetGUID = UnitGUID(targetUnit)
        local targetBoss, targetRole = GetPullInfo(targetGUID, targetName)
        targetType = targetBoss and TYPE_LABELS[targetRole or "boss"] or nil
    end

    local cast = ReadCast(unit)
    local x, y, z, mapId = UnitPosition(unit)
    local distance = mobUnit and DistanceBetweenUnits(unit, mobUnit) or nil

    return {
        name = name or "未知",
        guid = guid,
        unit = unit,
        classFile = classFile,
        classLocal = classLocal,
        role = role,
        health = health,
        healthMax = healthMax,
        healthPct = healthPct,
        connected = UnitIsConnected and UnitIsConnected(unit) and true or false,
        dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false,
        targetName = targetName,
        targetGUID = targetGUID,
        targetType = targetType,
        cast = cast,
        position = x and y and {
            x = x,
            y = y,
            z = z,
            mapId = mapId,
        } or nil,
        distance = distance,
    }
end

local function CaptureSnapshot(mobGUID, mobName, mobUnit)
    if mobUnit and (not UnitExists(mobUnit) or UnitGUID(mobUnit) ~= mobGUID) then
        mobUnit = nil
    end
    if not mobUnit then
        mobUnit = FindUnitForGUID(mobGUID)
    end

    local snapshot = {
        capturedAt = GetTime(),
        players = {},
        mob = {
            name = mobName,
            guid = mobGUID,
            npcId = NpcIDFromGUID(mobGUID),
            position = nil,
        },
        zone = GetRealZoneText and GetRealZoneText() or nil,
        instance = select(1, GetInstanceInfo()),
        difficulty = select(4, GetInstanceInfo()),
    }

    if mobUnit and UnitExists(mobUnit) then
        lastUnitByGUID[mobGUID] = mobUnit
        local x, y, z, mapId = UnitPosition(mobUnit)
        if x and y then
            snapshot.mob.position = { x = x, y = y, z = z, mapId = mapId }
        end
    end

    for _, unit in ipairs(groupUnits) do
        if UnitExists(unit) then
            local player = SnapshotPlayer(unit, mobUnit)
            snapshot.players[#snapshot.players + 1] = player
        end
    end

    return snapshot
end

-- ============================================================
-- 现代蓝灰界面组件
-- 参考 qwen-image-studio 的平静蓝色、卡片布局与清晰层级。
-- ============================================================

local UI = {}
UI.colors = {
    bg         = { 0.102, 0.165, 0.239, 0.940 },
    panel      = { 0.118, 0.176, 0.251, 0.970 },
    panelAlt   = { 0.153, 0.216, 0.298, 0.960 },
    panelHover = { 0.184, 0.255, 0.345, 0.980 },
    border     = { 0.200, 0.267, 0.333, 0.960 },
    accent     = { 0.259, 0.647, 0.961, 1.000 },
    accentHover = { 0.365, 0.706, 0.980, 1.000 },
    accentActive = { 0.176, 0.510, 0.820, 1.000 },
    accentSoft = { 0.259, 0.647, 0.961, 0.180 },
    ghost      = { 0.153, 0.216, 0.298, 0.180 },
    ghostBorder = { 0.200, 0.267, 0.333, 0.450 },
    text       = { 0.878, 0.878, 0.878, 1.000 },
    textDim    = { 0.667, 0.667, 0.667, 1.000 },
    success    = { 0.298, 0.686, 0.314, 1.000 },
    danger     = { 0.957, 0.263, 0.212, 1.000 },
    dangerHover = { 0.980, 0.350, 0.300, 1.000 },
    warning    = { 1.000, 0.596, 0.000, 1.000 },
}
UI.hex = {
    accent = "|cff42a5f5",
    text = "|cffe0e0e0",
    dim = "|cffaaaaaa",
    success = "|cff4caf50",
    danger = "|cfff44336",
    warning = "|cffff9800",
    neutral = "|r",
}
UI.backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

UI.ROUNDED_TEXTURE = "Interface\\AddOns\\WhoAdd\\Media\\RoundedRect"
UI.ROUNDED_BORDER_TEXTURE = "Interface\\AddOns\\WhoAdd\\Media\\RoundedRectBorder"
UI.ROUNDED_CORNER_RATIO = 0.25
UI.animations = {}
UI.motions = {}
UI.animationDriver = CreateFrame("Frame")
UI.animationDriver:Hide()

function UI.CopyColor(color)
    local red = color and color[1]
    local green = color and color[2]
    local blue = color and color[3]
    local alpha = color and color[4]
    return { red ~= nil and red or 1, green ~= nil and green or 1,
        blue ~= nil and blue or 1, alpha ~= nil and alpha or 1 }
end

function UI.ColorsEqual(left, right)
    if not left or not right then return false end
    return left[1] == right[1] and left[2] == right[2]
        and left[3] == right[3] and (left[4] or 1) == (right[4] or 1)
end

function UI.CreateRoundedLayer(frame, radius, level, sublevel, inset, texturePath)
    local layer = {
        frame = frame,
        pieces = {},
        radius = radius or 8,
        inset = inset or 0,
    }
    local corner = UI.ROUNDED_CORNER_RATIO
    local definitions = {
        { key = "TL", coords = { 0, corner, 0, corner } },
        { key = "T",  coords = { corner, 1 - corner, 0, corner } },
        { key = "TR", coords = { 1 - corner, 1, 0, corner } },
        { key = "L",  coords = { 0, corner, corner, 1 - corner } },
        { key = "C",  coords = { corner, 1 - corner, corner, 1 - corner } },
        { key = "R",  coords = { 1 - corner, 1, corner, 1 - corner } },
        { key = "BL", coords = { 0, corner, 1 - corner, 1 } },
        { key = "B",  coords = { corner, 1 - corner, 1 - corner, 1 } },
        { key = "BR", coords = { 1 - corner, 1, 1 - corner, 1 } },
    }
    for _, definition in ipairs(definitions) do
        local texture = frame:CreateTexture(nil, level or "BACKGROUND", nil, sublevel)
        texture:SetTexture(texturePath or UI.ROUNDED_TEXTURE)
        texture:SetTexCoord(definition.coords[1], definition.coords[2],
            definition.coords[3], definition.coords[4])
        texture:SetBlendMode("BLEND")
        layer.pieces[definition.key] = texture
    end
    return layer
end

function UI.LayoutRoundedLayer(layer)
    if not layer or not layer.frame then return end
    local frame = layer.frame
    local pixels = layer.pieces
    local width = frame:GetWidth() or 0
    local height = frame:GetHeight() or 0
    local inset = layer.inset or 0
    local innerWidth = math.max(0, width - inset * 2)
    local innerHeight = math.max(0, height - inset * 2)
    local radius = math.max(0, math.min(layer.radius or 0, innerWidth / 2, innerHeight / 2))

    if innerWidth <= 0 or innerHeight <= 0 then
        for _, texture in pairs(pixels) do texture:Hide() end
        return
    end
    for _, texture in pairs(pixels) do texture:Show() end

    pixels.TL:ClearAllPoints()
    pixels.TL:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    pixels.TL:SetSize(radius, radius)

    pixels.TR:ClearAllPoints()
    pixels.TR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    pixels.TR:SetSize(radius, radius)

    pixels.BL:ClearAllPoints()
    pixels.BL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    pixels.BL:SetSize(radius, radius)

    pixels.BR:ClearAllPoints()
    pixels.BR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    pixels.BR:SetSize(radius, radius)

    pixels.T:ClearAllPoints()
    pixels.T:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + radius, -inset)
    pixels.T:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(inset + radius), -inset)
    pixels.T:SetHeight(radius)

    pixels.B:ClearAllPoints()
    pixels.B:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset + radius, inset)
    pixels.B:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(inset + radius), inset)
    pixels.B:SetHeight(radius)

    pixels.L:ClearAllPoints()
    pixels.L:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -(inset + radius))
    pixels.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset + radius)
    pixels.L:SetWidth(radius)

    pixels.R:ClearAllPoints()
    pixels.R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -(inset + radius))
    pixels.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset + radius)
    pixels.R:SetWidth(radius)

    pixels.C:ClearAllPoints()
    pixels.C:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + radius, -(inset + radius))
    pixels.C:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(inset + radius), inset + radius)
end

function UI.SetRoundedLayerColor(layer, color)
    if not layer or not color then return end
    local red, green, blue = color[1] or 1, color[2] or 1, color[3] or 1
    local alpha = color[4] or 1
    for _, texture in pairs(layer.pieces) do
        texture:SetVertexColor(red, green, blue, alpha)
    end
end

function UI.LayoutRounded(frame)
    if not frame then return end
    UI.LayoutRoundedLayer(frame._roundedBorder)
    UI.LayoutRoundedLayer(frame._roundedFill)
end

function UI.SetRoundedColors(frame, bg, border)
    frame._currentBg = UI.CopyColor(bg)
    frame._currentBorder = UI.CopyColor(border)
    UI.SetRoundedLayerColor(frame._roundedBorder, frame._currentBorder)
    UI.SetRoundedLayerColor(frame._roundedFill, frame._currentBg)
end

function UI.LerpColor(from, to, progress)
    return {
        (from[1] or 1) + ((to[1] or 1) - (from[1] or 1)) * progress,
        (from[2] or 1) + ((to[2] or 1) - (from[2] or 1)) * progress,
        (from[3] or 1) + ((to[3] or 1) - (from[3] or 1)) * progress,
        (from[4] or 1) + ((to[4] or 1) - (from[4] or 1)) * progress,
    }
end

function UI.AnimateVisual(frame, bg, border, duration)
    if not frame or not frame._roundedBorder then return end
    bg = bg or UI.colors.panel
    border = border or UI.colors.border
    duration = tonumber(duration) or 0.14

    if duration <= 0 or not frame:IsShown() then
        UI.animations[frame] = nil
        UI.SetRoundedColors(frame, bg, border)
        frame._targetBg = UI.CopyColor(bg)
        frame._targetBorder = UI.CopyColor(border)
        return
    end
    if frame._targetBg and frame._targetBorder
        and UI.ColorsEqual(frame._targetBg, bg) and UI.ColorsEqual(frame._targetBorder, border) then
        return
    end

    UI.animations[frame] = {
        start = GetTime(),
        duration = duration,
        fromBg = UI.CopyColor(frame._currentBg or bg),
        fromBorder = UI.CopyColor(frame._currentBorder or border),
        toBg = UI.CopyColor(bg),
        toBorder = UI.CopyColor(border),
    }
    frame._targetBg = UI.CopyColor(bg)
    frame._targetBorder = UI.CopyColor(border)
    UI.animationDriver:Show()
end

function UI.PlayMotion(frame, alphaFrom, alphaTo, scaleFrom, scaleTo, duration)
    if not frame then return end
    duration = tonumber(duration) or 0.16
    frame:SetAlpha(alphaFrom or 0)
    frame:SetScale(scaleFrom or 1)
    UI.motions[frame] = {
        start = GetTime(),
        duration = math.max(duration, 0.01),
        alphaFrom = alphaFrom or 0,
        alphaTo = alphaTo or 1,
        scaleFrom = scaleFrom or 1,
        scaleTo = scaleTo or 1,
    }
    UI.animationDriver:Show()
end

function UI.DriveAnimations()
    local now = GetTime()
    local active = false

    for frame, animation in pairs(UI.animations) do
        local progress = math.min(1, (now - animation.start) / animation.duration)
        local eased = 1 - (1 - progress) ^ 3
        if progress >= 1 then
            UI.animations[frame] = nil
            UI.SetRoundedColors(frame, animation.toBg, animation.toBorder)
        else
            UI.SetRoundedColors(frame,
                UI.LerpColor(animation.fromBg, animation.toBg, eased),
                UI.LerpColor(animation.fromBorder, animation.toBorder, eased))
            active = true
        end
    end

    for frame, motion in pairs(UI.motions) do
        local progress = math.min(1, (now - motion.start) / motion.duration)
        local eased = 1 - (1 - progress) ^ 3
        frame:SetAlpha(motion.alphaFrom + (motion.alphaTo - motion.alphaFrom) * eased)
        frame:SetScale(motion.scaleFrom + (motion.scaleTo - motion.scaleFrom) * eased)
        if progress >= 1 then
            UI.motions[frame] = nil
            frame:SetAlpha(motion.alphaTo)
            frame:SetScale(motion.scaleTo)
        else
            active = true
        end
    end

    if not active then UI.animationDriver:Hide() end
end

UI.animationDriver:SetScript("OnUpdate", UI.DriveAnimations)

function UI.ApplyCard(frame, bg, border, radius)
    if not frame or not frame.CreateTexture then return false end
    bg = bg or UI.colors.panel
    border = border or UI.colors.border
    radius = radius or 8

    local ok, err = pcall(function()
        if not frame._roundedBorder then
            frame._roundedFill = UI.CreateRoundedLayer(frame, radius, "BACKGROUND", -8, 0,
                UI.ROUNDED_TEXTURE)
            frame._roundedBorder = UI.CreateRoundedLayer(frame, radius, "BACKGROUND", -7, 0,
                UI.ROUNDED_BORDER_TEXTURE)
            if frame.HookScript and not frame._roundedSizeHooked then
                frame._roundedSizeHooked = true
                frame:HookScript("OnSizeChanged", function(self) UI.LayoutRounded(self) end)
            end
        end

        frame._roundedRadius = radius
        frame._roundedBorder.radius = radius
        frame._roundedBorder.inset = 0
        frame._roundedFill.radius = radius
        frame._roundedFill.inset = 0
        UI.LayoutRounded(frame)

        frame._targetBg = UI.CopyColor(bg)
        frame._targetBorder = UI.CopyColor(border)
        UI.SetRoundedColors(frame, bg, border)
    end)
    if not ok then
        frame._roundedBuildError = tostring(err)
        return false
    end
    return true
end

function UI.CreateCard(parent, bg, border, radius)
    local card = CreateFrame("Frame", nil, parent)
    UI.ApplyCard(card, bg, border, radius or 8)
    return card
end

function UI.Label(parent, text, font, color, width)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetText(text or "")
    color = color or UI.colors.text
    label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    if width then label:SetWidth(width) end
    label:SetJustifyH("LEFT")
    return label
end

function UI.Divider(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    SetSolidColor(line, UI.colors.border[1], UI.colors.border[2], UI.colors.border[3], 0.72)
    line:SetHeight(1)
    return line
end

function UI.Button(parent, text, width, height, kind)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 96, height or 32)
    button.kind = kind or "secondary"
    button.isSelected = false
    button.isHovered = false
    button.isPressed = false
    UI.ApplyCard(button, UI.colors.panelAlt, UI.colors.border, 4)

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text or "")
    button.Text = label

    function button:SetText(value)
        self.Text:SetText(value or "")
    end
    function button:GetText()
        return self.Text:GetText()
    end
    function button:SetSelected(value)
        self.isSelected = value and true or false
        self:RefreshVisual()
    end
    function button:RefreshVisual(duration)
        local enabled = self:IsEnabled()
        local primary = self.kind == "primary"
        local danger = self.kind == "danger"
        local ghost = self.kind == "ghost"
        local bg, border, textColor

        if primary then
            bg = self.isPressed and UI.colors.accentActive
                or (self.isHovered and UI.colors.accentHover or UI.colors.accent)
            border = bg
            textColor = { 1, 1, 1, 1 }
        elseif danger then
            bg = self.isPressed and UI.colors.danger
                or (self.isHovered and UI.colors.dangerHover or UI.colors.danger)
            border = bg
            textColor = { 1, 1, 1, 1 }
        elseif ghost then
            bg = self.isHovered and UI.colors.panelAlt or UI.colors.ghost
            border = self.isHovered and UI.colors.accent or UI.colors.ghostBorder
            textColor = self.isHovered and UI.colors.accent or UI.colors.text
        elseif self.isSelected then
            bg = self.isHovered and UI.colors.panelHover or UI.colors.accentSoft
            border = UI.colors.accent
            textColor = UI.colors.accent
        else
            bg = self.isHovered and UI.colors.panelHover or UI.colors.panelAlt
            border = self.isHovered and UI.colors.accent or UI.colors.border
            textColor = self.isHovered and UI.colors.accent or UI.colors.text
        end

        UI.AnimateVisual(self, bg, border, duration or 0.14)
        self.Text:SetTextColor(textColor[1], textColor[2], textColor[3], enabled and 1 or 0.42)
        self:SetAlpha(enabled and 1 or 0.46)
    end

    button:SetScript("OnEnter", function(self)
        self.isHovered = true
        self:RefreshVisual()
    end)
    button:SetScript("OnLeave", function(self)
        self.isHovered = false
        self.isPressed = false
        self:SetScale(1)
        self:RefreshVisual()
    end)
    button:SetScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        self.isPressed = true
        self:SetScale(0.985)
        self:RefreshVisual(0.06)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.isPressed = false
        self:SetScale(1)
        self:RefreshVisual()
    end)
    button:SetScript("OnEnable", function(self) self:RefreshVisual() end)
    button:SetScript("OnDisable", function(self) self:RefreshVisual() end)
    button:RefreshVisual(0)
    return button
end

function UI.Checkbox(parent, text, width, onClick)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(width or 230, 28)
    check.isHovered = false

    local box = CreateFrame("Frame", nil, check)
    box:SetSize(18, 18)
    box:SetPoint("LEFT", 0, 0)
    UI.ApplyCard(box, UI.colors.panelAlt, UI.colors.border, 4)
    check.Box = box

    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetSize(14, 14)
    mark:SetPoint("CENTER", 0, 0)
    mark:SetVertexColor(1, 1, 1, 1)
    check.Mark = mark

    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", box, "RIGHT", 9, 0)
    label:SetText(text or "")
    label:SetTextColor(UI.colors.text[1], UI.colors.text[2], UI.colors.text[3], 1)
    check.Text = label

    function check:RefreshVisual(duration)
        local checked = self:GetChecked() and true or false
        local enabled = self:IsEnabled()
        local bg = checked and UI.colors.accent
            or (self.isHovered and UI.colors.panelHover or UI.colors.panelAlt)
        local border = (self.isHovered or checked) and UI.colors.accent or UI.colors.border
        UI.AnimateVisual(self.Box, bg, border, duration or 0.14)
        if self.Mark.SetShown then self.Mark:SetShown(checked) elseif checked then self.Mark:Show() else self.Mark:Hide() end
        local color = (self.isHovered or checked) and UI.colors.accent or UI.colors.text
        self.Text:SetTextColor(color[1], color[2], color[3], enabled and 1 or 0.45)
        self:SetAlpha(enabled and 1 or 0.55)
    end

    local nativeSetChecked = check.SetChecked
    function check:SetChecked(value)
        nativeSetChecked(self, value and true or false)
        self:RefreshVisual()
    end

    check:SetScript("OnEnter", function(self)
        self.isHovered = true
        self:RefreshVisual()
    end)
    check:SetScript("OnLeave", function(self)
        self.isHovered = false
        self.Box:SetScale(1)
        self:RefreshVisual()
    end)
    check:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self.Box:SetScale(0.92) end
    end)
    check:SetScript("OnMouseUp", function(self)
        self.Box:SetScale(1)
    end)
    check:SetScript("OnClick", function(self)
        self:RefreshVisual()
        if onClick then onClick(self:GetChecked() and true or false) end
    end)
    check:SetScript("OnEnable", function(self) self:RefreshVisual() end)
    check:SetScript("OnDisable", function(self) self:RefreshVisual() end)
    check:RefreshVisual(0)
    return check
end

function UI.EditBox(parent, name, width, height, multiline)
    local edit = CreateFrame("EditBox", name, parent)
    edit:SetSize(width or 220, height or 32)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextColor(UI.colors.text[1], UI.colors.text[2], UI.colors.text[3], 1)
    edit:SetTextInsets(12, 12, 8, 8)
    edit:SetMultiLine(multiline and true or false)
    if edit.SetJustifyH then edit:SetJustifyH("LEFT") end
    if multiline then
        if edit.SetJustifyV then edit:SetJustifyV("TOP") end
    else
        edit:SetMaxLetters(80)
    end
    UI.ApplyCard(edit, UI.colors.panelAlt, UI.colors.border, 4)
    if edit.HookScript then
        edit:HookScript("OnEditFocusGained", function(self)
            UI.AnimateVisual(self, UI.colors.panelHover, UI.colors.accent, 0.14)
        end)
        edit:HookScript("OnEditFocusLost", function(self)
            UI.AnimateVisual(self, UI.colors.panelAlt, UI.colors.border, 0.16)
        end)
    else
        edit:SetScript("OnEditFocusGained", function(self)
            UI.AnimateVisual(self, UI.colors.panelHover, UI.colors.accent, 0.14)
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            UI.AnimateVisual(self, UI.colors.panelAlt, UI.colors.border, 0.16)
        end)
    end
    return edit
end

function UI.CreateScroll(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    scroll:EnableMouseWheel(true)
    scroll:EnableMouse(true)

    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 7, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 7, 0)
    UI.ApplyCard(track, UI.colors.bg, UI.colors.bg, 2)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(12)
    slider:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 4, 0)
    slider:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 4, 0)
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(1)
    slider:SetThumbTexture(UI.ROUNDED_TEXTURE)
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(7, 28)
        thumb:SetVertexColor(UI.colors.accent[1], UI.colors.accent[2], UI.colors.accent[3], 0.9)
    end

    local function UpdateScrollRange()
        local content = scroll:GetScrollChild()
        local viewHeight = scroll:GetHeight() or 0
        local contentHeight = content and content:GetHeight() or 0
        local maximum = math.max(0, contentHeight - viewHeight)
        slider:SetMinMaxValues(0, maximum)
        if slider:GetValue() > maximum then slider:SetValue(maximum) end
        track:SetShown(maximum > 0.5)
        slider:SetShown(maximum > 0.5)
    end

    slider:SetScript("OnValueChanged", function(self, value)
        scroll:SetVerticalScroll(value or 0)
    end)
    scroll:SetScript("OnVerticalScroll", function(_, offset)
        slider:SetValue(offset or 0)
    end)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local minimum, maximum = slider:GetMinMaxValues()
        local value = slider:GetValue() - ((delta or 0) * 46)
        slider:SetValue(math.max(minimum or 0, math.min(maximum or 0, value)))
        UpdateScrollRange()
    end)
    scroll:SetScript("OnSizeChanged", UpdateScrollRange)
    scroll.UpdateScrollRange = UpdateScrollRange
    return scroll, slider
end

do
    local dialog = CreateFrame("Frame", "WhoAddConfirmDialog", UIParent)
    dialog:SetAllPoints(UIParent)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:EnableMouse(true)
    dialog:EnableMouseWheel(true)
    dialog:Hide()

    local shade = dialog:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    SetSolidColor(shade, 0.015, 0.025, 0.040, 0.62)

    local card = UI.CreateCard(dialog, UI.colors.panel, UI.colors.border, 8)
    card:SetSize(440, 190)
    card:SetPoint("CENTER")

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\WhoAdd\\Media\\WhoAddIcon")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 18, -16)

    local title = UI.Label(card, "", "GameFontNormalLarge", UI.colors.accent)
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)

    local message = UI.Label(card, "", "GameFontHighlightSmall", UI.colors.text, 396)
    message:SetPoint("TOPLEFT", 18, -58)
    message:SetJustifyH("LEFT")
    message:SetWordWrap(true)

    local cancel = UI.Button(card, "取消", 96, 32, "secondary")
    cancel:SetPoint("BOTTOMRIGHT", -18, 16)

    local accept = UI.Button(card, "确定", 96, 32, "primary")
    accept:SetPoint("RIGHT", cancel, "LEFT", -8, 0)

    local function HideConfirm()
        dialog:Hide()
        dialog:EnableKeyboard(false)
        UI.confirmAccept = nil
    end

    cancel:SetScript("OnClick", HideConfirm)
    accept:SetScript("OnClick", function()
        local callback = UI.confirmAccept
        HideConfirm()
        if callback then callback() end
    end)
    dialog:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then HideConfirm() end
    end)

    UI.confirmDialog = dialog
    UI.confirmCard = card
    UI.ShowConfirm = function(titleText, messageText, acceptText, callback, danger)
        title:SetText(titleText or "请确认")
        message:SetText(messageText or "")
        accept:SetText(acceptText or "确定")
        accept.kind = danger and "danger" or "primary"
        accept:RefreshVisual(0)
        UI.confirmAccept = callback
        dialog:Show()
        dialog:Raise()
        dialog:EnableKeyboard(true)
        UI.PlayMotion(card, 0, 1, 0.96, 1, 0.18)
    end
end

-- ============================================================
-- 通报、弹窗和声音
-- ============================================================

local function PlayAlertSound(force)
    if not force and not settings.soundEnabled then return end
    local soundKit = tonumber(settings.soundKit) or DEFAULT_SOUND_KIT
    if type(PlaySound) == "function" then
        local ok = pcall(PlaySound, soundKit, "Master")
        if ok then return end
    end
    if type(PlaySoundFile) == "function" then
        pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav", "Master")
    end
end

local popup = CreateFrame("Frame", "WhoAddPullPopup", UIParent)
popup:SetSize(500, 126)
popup:SetPoint("TOP", UIParent, "TOP", 0, -150)
popup:SetFrameStrata("FULLSCREEN_DIALOG")
popup:SetToplevel(true)
popup:EnableMouse(true)
UI.ApplyCard(popup, UI.colors.panel, UI.colors.border, 8)
popup:Hide()

local popupIcon = popup:CreateTexture(nil, "ARTWORK")
popupIcon:SetTexture("Interface\\AddOns\\WhoAdd\\Media\\WhoAddIcon")
popupIcon:SetSize(26, 26)
popupIcon:SetPoint("TOPLEFT", 18, -14)

local popupTitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
popupTitle:SetPoint("LEFT", popupIcon, "RIGHT", 10, 0)
popupTitle:SetText(UI.hex.accent .. "WHOADD|r  " .. UI.hex.dim .. "开怪提醒|r")

local popupMain = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
popupMain:SetPoint("TOPLEFT", 54, -44)
popupMain:SetWidth(424)
popupMain:SetJustifyH("LEFT")
popupMain:SetWordWrap(true)

local popupSub = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
popupSub:SetPoint("TOPLEFT", 54, -72)
popupSub:SetWidth(424)
popupSub:SetJustifyH("LEFT")
popupSub:SetWordWrap(true)

local popupNpc = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
popupNpc:SetPoint("TOPLEFT", 54, -100)
popupNpc:SetWidth(424)
popupNpc:SetJustifyH("LEFT")
popupNpc:SetWordWrap(true)
popupNpc:Hide()

local popupFooter = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
popupFooter:SetPoint("BOTTOMLEFT", 18, 11)
popupFooter:SetText(UI.hex.dim .. "点击此卡片查看对应开怪快照|r")

popup.fadeAt = 0
popup.popStartedAt = nil
popup:SetScript("OnUpdate", function(self, elapsed)
    if not self:IsShown() then return end
    local now = GetTime()
    if self.popStartedAt then
        local progress = math.min(1, (now - self.popStartedAt) / 0.18)
        local eased = 1 - (1 - progress) ^ 3
        self:SetAlpha(0.15 + 0.85 * eased)
        self:SetScale(0.96 + 0.04 * eased)
        if progress >= 1 then self.popStartedAt = nil end
    end
    if now < self.fadeAt then return end
    local alpha = self:GetAlpha() - elapsed / 1.2
    if alpha <= 0 then
        self:SetAlpha(1)
        self:SetScale(1)
        self.popStartedAt = nil
        self:Hide()
    else
        self:SetAlpha(alpha)
    end
end)

popup:SetScript("OnMouseUp", function()
    if lastPopupRecord and SelectRecord then
        SelectRecord(lastPopupRecord)
        if SelectTab then SelectTab(1) end
        if listFrame then listFrame:Show() end
    end
end)

local function ShowPullPopup(record, force)
    if (not force and not settings.popupEnabled) or not record then return false end
    lastPopupRecord = record

    local popupType = record.bossRelated and TYPE_LABELS.boss
        or TYPE_LABELS[record.role or "trash"] or "开怪"
    local distance = record.distance and string.format(" · %.1f码", record.distance) or ""
    popupMain:SetText(string.format("%s%s|r  %s  %s%s|r%s",
        UI.hex.accent, record.puller or "未知", record.action or "触发了",
        UI.hex.text, record.mobDisplayName or record.mobName or "未知", distance))

    local target = record.bossName and ("首领: " .. record.bossName) or ("类型: " .. popupType)
    popupSub:SetText(string.format("%s%s · %s|r", UI.hex.dim,
        target, record.sourceLabel or record.source or "未知来源"))

    if record.npcClickerText and record.npcClickerText ~= "" then
        popupNpc:SetText(UI.hex.accent .. "对话开怪者|r\n" ..
            UI.hex.dim .. string.gsub(record.npcClickerText, "、", "\n") .. "|r")
        popupNpc:Show()
        popup:SetHeight(math.min(390, math.max(132, 116 + popupNpc:GetStringHeight())))
    else
        popupNpc:Hide()
        popup:SetHeight(126)
    end

    popup:SetAlpha(0.15)
    popup:SetScale(0.96)
    popup.popStartedAt = GetTime()
    popup.fadeAt = GetTime() + 5
    popup:Show()
    return true
end

local function SendMessage(message)
    message = TrimMessage(message)
    if IsInRaid() then
        SendChatMessage(message, "RAID")
    elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        SendChatMessage(message, "INSTANCE_CHAT")
    elseif IsInGroup() then
        SendChatMessage(message, "PARTY")
    else
        print("|cff66ccff[WhoAdd]|r " .. message)
    end
end

local function RenderTemplate(record, templateOverride)
    local template = templateOverride or settings.template
    if type(template) ~= "string" or template == "" then
        template = DEFAULT_TEMPLATE
    end

    local distance = ""
    if settings.includeDistance and record.distance then
        distance = string.format("（距怪 %.1f 码）", record.distance)
    end

    local values = {
        puller = record.puller or "未知",
        mob = record.mobDisplayName or record.mobName or "未知",
        boss = record.bossName or record.mobDisplayName or record.mobName or "未知",
        raid = record.raid or "",
        type = record.action or "触发了",
        time = record.timeText or "",
        distance = distance,
        source = record.sourceLabel or record.source or "",
        npcid = record.npcID and tostring(record.npcID) or "",
        count = record.snapshot and tostring(#record.snapshot.players) or "0",
        npc = record.npcClickerChat and ("对话人：" .. record.npcClickerChat) or "",
        -- 兼容 4.6.9 及更早模板；构建器和新存档统一使用 {npc}。
        dialogue = record.npcClickerChat and ("对话人：" .. record.npcClickerChat) or "",
    }

    local message = template:gsub("{(%w+)}", function(key)
        return values[key] or ""
    end)
    message = message:gsub("[ \t]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return TrimMessage(message)
end

local function QueueAnnouncement(message)
    local items = pendingAnnouncements.items
    items[#items + 1] = message
    if #items > 20 then table.remove(items, 1) end
    if not AnyoneInCombat() then
        pendingAnnouncements.readyAt = math.max(
            pendingAnnouncements.readyAt,
            GetTime() + (tonumber(settings.delaySeconds) or 3))
    end
end

local function FlushPendingAnnouncements()
    local items = pendingAnnouncements.items
    if #items == 0 then return end
    local now = GetTime()
    if now < pendingAnnouncements.readyAt then return end
    if now < pendingAnnouncements.nextSendAt then return end
    if AnyoneInCombat() then return end

    local message = table.remove(items, 1)
    if message then
        SendMessage(message)
        pendingAnnouncements.nextSendAt = now + 0.35
    end
    if #items == 0 then
        pendingAnnouncements.readyAt = 0
        pendingAnnouncements.waitingCombat = false
    end
end

local function NotifyAllowed(record)
    if record.userTest then return true end
    if settings.reportMode == "all" then return true end
    if settings.reportMode == "boss" then return record.bossRelated == true end
    return false
end

local function CanAddBePullEvidence(npcId, boss)
    npcId = tonumber(npcId)
    if not npcId or IGNORED_ADD_NPCS[npcId] then return false end
    local knownBoss = boss or BOSS_BY_ID[npcId]
    local isBossAdd = boss ~= nil or (knownBoss and knownBoss.roleById[npcId] == "add")
    if not PULL_EVIDENCE_ADD_NPCS[npcId] and not isBossAdd then return false end
    if bossReported or initialAddReports >= 1 then return false end
    return true
end

local function BuildRecord(info, snapshot)
    local now = GetTime()
    local mobName = info.mobName or "未知NPC"
    local npcId = NpcIDFromGUID(info.guid)
    local role = info.role or "trash"
    local boss = info.boss
    local displayName = info.displayName or ADD_NAME_OVERRIDES[npcId] or mobName
    local isBossEvidence = role == "add" or role == "opening" or role == "dialogue"
    if isBossEvidence and boss then displayName = boss.name end
    local typeLabel = TYPE_LABELS[role] or TYPE_LABELS.trash
    if boss and isBossEvidence then
        typeLabel = "首领开怪"
    end
    local encounter = activeEncounter and CopyTable(activeEncounter) or nil

    local record = {
        id = nextPullID,
        at = now,
        epoch = time(),
        timeText = date("%H:%M:%S"),
        dateText = date("%Y-%m-%d %H:%M:%S"),
        puller = info.puller or "未知",
        pullerGUID = info.pullerGUID,
        mobName = mobName,
        mobDisplayName = displayName,
        triggerMobName = isBossEvidence and mobName ~= displayName and mobName or nil,
        mobGUID = info.guid,
        npcID = npcId,
        role = role,
        typeLabel = typeLabel,
        bossName = boss and boss.name or nil,
        bossRelated = boss ~= nil,
        raid = boss and boss.raid or snapshot.zone or (GetRealZoneText and GetRealZoneText()) or nil,
        source = info.source or "SCAN",
        sourceLabel = SOURCE_LABELS[info.source] or info.source,
        action = info.action or "触发了",
        evidence = info.evidence,
        encounter = encounter,
        npcClickers = info.npcClickers,
        npcClickerText = info.npcClickerText,
        npcClickerChat = info.npcClickerChat,
        snapshot = snapshot,
        test = info.test == true,
        userTest = info.userTest == true,
    }

    local pullerDistance
    for _, player in ipairs(snapshot.players or {}) do
        if (record.pullerGUID and player.guid == record.pullerGUID)
            or (not record.pullerGUID and player.name == record.puller) then
            pullerDistance = player.distance
            break
        end
    end
    record.distance = pullerDistance or snapshot.localDistance

    nextPullID = nextPullID + 1
    return record
end

local function ReportPull(info)
    if not info or not info.guid then return nil end
    if suppressCurrentCombat then return nil end
    if reportedMobs[info.guid] or deadMobs[info.guid] then return nil end
    DebugPrint(string.format("尝试记录 %s (%s)", tostring(info.mobName), tostring(info.guid)))

    local role = info.role or "trash"
    local npcId = NpcIDFromGUID(info.guid)
    local bossKey = info.boss and info.boss.name
        and ("boss:" .. tostring(info.boss.raid or "") .. ":" .. info.boss.name) or nil
    if bossKey and reportedMobs[bossKey] then return nil end
    local encounterId = activeEncounter and activeEncounter.id
    if npcId and IGNORED_ADD_NPCS[npcId] then return nil end
    if role == "add" and not CanAddBePullEvidence(npcId, info.boss) then return nil end
    if role == "boss" and encounterId and reportedEncounterBosses[encounterId] then
        return nil
    end
    if activeEncounter and activeEncounter.startedAt and role ~= "boss"
        and role ~= "opening" and role ~= "dialogue"
        and (role ~= "add" or not CanAddBePullEvidence(npcId, info.boss)) then
        return nil
    end
    if not info.boss and activeEncounter and bossReported and bossEngagedAt
        and GetTime() - bossEngagedAt > 12 then
        return nil
    end

    local attachDialogue = role == "boss"
        or (role == "add" and IsTocDialogueBoss(info.boss))
    if attachDialogue and not info.npcClickers then
        local clickerEncounter = info.bossName
            or (activeEncounter and activeEncounter.name)
            or (info.boss and info.boss.name)
        local clickers, fullText, chatText = GetNpcInteractionSummary(clickerEncounter)
        if #clickers > 0 then
            info.npcClickers = clickers
            info.npcClickerText = fullText
            info.npcClickerChat = chatText
        end
    end

    reportedMobs[info.guid] = GetTime()
    if bossKey then reportedMobs[bossKey] = GetTime() end

    local mobUnit = info.unit
    if mobUnit and UnitGUID(mobUnit) == info.guid then
        lastUnitByGUID[info.guid] = mobUnit
    else
        mobUnit = FindUnitForGUID(info.guid)
    end

    local snapshot = info.snapshot
    if type(snapshot) ~= "table" then
        local ok
        ok, snapshot = pcall(CaptureSnapshot, info.guid, info.mobName, mobUnit)
        if not ok or type(snapshot) ~= "table" then
            DebugPrint("快照失败: " .. tostring(snapshot))
            snapshot = { players = {}, mob = { name = info.mobName, guid = info.guid } }
        end
    end

    local localDistance
    for _, player in ipairs(snapshot.players or {}) do
        if UnitIsUnit(player.unit, "player") then
            localDistance = player.distance
            break
        end
    end
    snapshot.localDistance = localDistance

    local record = BuildRecord(info, snapshot)
    table.insert(pullLog, 1, record)
    SaveHistory()

    firstPullReported = true
    if role == "boss" then
        activeBossGUID = info.guid
        bossReported = true
        bossEngagedAt = record.at
        if encounterId then
            reportedEncounterBosses[encounterId] = true
        end
    elseif role == "opening" or role == "dialogue" then
        bossReported = true
        bossEngagedAt = record.at
    elseif role == "add" then
        initialAddReports = initialAddReports + 1
        if info.boss then
            bossReported = true
            bossEngagedAt = record.at
        end
    end

    if not selectedRecord then selectedRecord = record end

    if listFrame and listFrame:IsShown() then
        if selectedTab == 1 then RefreshRecordList() end
    end

    if NotifyAllowed(record) then
        if settings.popupEnabled then ShowPullPopup(record) end
        if settings.soundEnabled then PlayAlertSound() end

        local message = RenderTemplate(record)
        if record.npcClickerChat and record.npcClickerChat ~= ""
            and not message:find(record.npcClickerChat, 1, true) then
            message = TrimMessage(message .. " 对话人：" .. record.npcClickerChat)
        end
        record.message = message
        if settings.textEnabled then
            if settings.delayOutOfCombat then
                QueueAnnouncement(message)
            else
                SendMessage(message)
            end
        end
    end

    if info.npcClickers and #info.npcClickers > 0 then
        dialogueFallbackGeneration = dialogueFallbackGeneration + 1
        ClearNpcInteractions()
    end

    return record
end

local function FindEncounterBossUnit()
    for index = 1, 5 do
        local unit = "boss" .. index
        if UnitExists(unit) and not UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid then return guid, unit end
        end
    end
    return nil, nil
end

local function ReportDialogueEncounter(encounterName)
    local clickers, fullText, chatText = GetNpcInteractionSummary(encounterName)
    if #clickers == 0 then return nil end

    local boss = BOSS_BY_NAME[encounterName] or RegisterEncounterBoss(encounterName)
    local firstClicker = clickers[1]
    local bossGUID, bossUnit = FindEncounterBossUnit()
    if not bossGUID and firstClicker.npcGUID then
        bossGUID = firstClicker.npcGUID
        bossUnit = FindUnitForGUID(bossGUID)
    end
    if not bossGUID then
        local encounterId = activeEncounter and activeEncounter.id or encounterName or "encounter"
        bossGUID = "Encounter-" .. tostring(encounterId) .. "-" .. tostring(math.floor(time()))
    end

    return ReportPull({
        guid = bossGUID,
        mobName = firstClicker.npcName or encounterName or (boss and boss.name) or "未知首领",
        unit = bossUnit,
        boss = boss,
        role = firstClicker.interactionRole or "dialogue",
        puller = firstClicker.name or "对话触发",
        pullerGUID = firstClicker.guid,
        source = firstClicker.interactionRole == "opening" and "OPENING" or "ENCOUNTER",
        action = firstClicker.interactionRole == "opening" and "选中了开怪NPC" or "触发了对话开怪",
        evidence = "NPC_INTERACTION",
        npcClickers = clickers,
        npcClickerText = fullText,
        npcClickerChat = chatText,
        snapshot = CaptureSnapshot(bossGUID, firstClicker.npcName or encounterName, bossUnit),
    })
end

local function ScheduleDialogueFallback(boss, delay)
    if not boss or not IsTocDialogueBoss(boss) then return end
    dialogueFallbackGeneration = dialogueFallbackGeneration + 1
    local generation = dialogueFallbackGeneration
    After(delay or 0.8, function()
        if generation ~= dialogueFallbackGeneration or bossReported then return end
        local bossKey = "boss:" .. tostring(boss.raid or "") .. ":" .. tostring(boss.name)
        if reportedMobs[bossKey] then return end
        local record = ReportDialogueEncounter(boss.name)
        if record then ClearNpcInteractions() end
    end)
end

-- ============================================================
-- 开怪检测
-- ============================================================

local function QueueSpecialTarget(targetGUID, targetName, targetUnit, pullerName, pullerGUID, source)
    if not targetGUID or reportedMobs[targetGUID] or deadMobs[targetGUID] then return end
    local npcId = NpcIDFromGUID(targetGUID)
    local opening = npcId and OPENING_BY_ID[npcId]
    if not opening then return end
    DebugPrint("记录开怪NPC候选: " .. tostring(targetName) .. " / " .. tostring(pullerName))

    local now = GetTime()
    local list = specialCandidates[targetGUID]
    if not list then
        list = {}
        specialCandidates[targetGUID] = list
    end

    local key = pullerGUID or pullerName or "unknown"
    local candidate
    for i = 1, #list do
        if list[i].pullerKey == key then
            candidate = list[i]
            break
        end
    end

    local cast = recentCastByDest[targetGUID]
    if candidate then
        candidate.seenAt = now
        candidate.unit = targetUnit
        if cast and now - cast.at <= ACTION_LOOKUP_WINDOW then
            candidate.spell = cast.spell
        end
    else
        local ok, snapshot = pcall(CaptureSnapshot, targetGUID, targetName, targetUnit)
        list[#list + 1] = {
            guid = targetGUID,
            name = targetName,
            unit = targetUnit,
            pullerKey = key,
            puller = pullerName or "未知",
            pullerGUID = pullerGUID,
            firstAt = now,
            seenAt = now,
            source = source or "SPECIAL",
            boss = opening.boss,
            role = opening.role,
            spell = cast and now - cast.at <= ACTION_LOOKUP_WINDOW and cast.spell or nil,
            snapshot = ok and snapshot or nil,
        }
    end
end

local function PruneSpecialCandidates()
    local now = GetTime()
    for guid, list in pairs(specialCandidates) do
        for i = #list, 1, -1 do
            if now - list[i].firstAt > SPECIAL_TARGET_WINDOW then
                table.remove(list, i)
            end
        end
        if #list == 0 then specialCandidates[guid] = nil end
    end
end

local function FinalizeSpecialCandidates(encounterName)
    PruneSpecialCandidates()
    local now = GetTime()
    local best

    for _, list in pairs(specialCandidates) do
        for _, candidate in ipairs(list) do
            local matches = true
            if encounterName and candidate.role ~= "dialogue"
                and candidate.boss and candidate.boss.name ~= encounterName then
                matches = false
            end
            if matches and now - candidate.firstAt <= SPECIAL_TARGET_WINDOW
                and not reportedMobs[candidate.guid]
                and (not best or candidate.seenAt > best.seenAt) then
                best = candidate
            end
        end
    end

    if not best then return nil end
    DebugPrint("确认开怪NPC候选: " .. tostring(best.name) .. " / " .. tostring(best.puller))
    local encounterBoss = encounterName and BOSS_BY_NAME[encounterName] or nil
    local boss = encounterBoss or best.boss
    local action
    if best.role == "dialogue" then
        action = "触发了对话开怪"
    elseif best.spell then
        action = "用 " .. best.spell .. " 触发了"
    else
        action = "选中了开怪NPC"
    end

    local record = ReportPull({
        guid = best.guid,
        mobName = best.name,
        unit = best.unit,
        boss = boss,
        role = best.role,
        puller = best.puller,
        pullerGUID = best.pullerGUID,
        source = "SPECIAL",
        action = action,
        evidence = best.source,
        snapshot = best.snapshot,
    })

    if record then
        specialCandidates[best.guid] = nil
        recentCastByDest[best.guid] = nil
    end
    return record
end

local function ScheduleSpecialFinalize(delay, encounterName)
    After(delay or 0.15, function()
        FinalizeSpecialCandidates(encounterName)
    end)
end

local function CheckSpecialTargetForUnit(unit)
    TrackNpcInteraction(unit)
end

local function EvaluateNpcTarget(unit, source)
    if not unit or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) or IsGroupUnit(unit) then return end

    local guid = UnitGUID(unit)
    if not guid or reportedMobs[guid] or deadMobs[guid] then return end

    local name = UnitName(unit)
    local boss, role, npcId = GetPullInfo(guid, name)
    if role == "opening" or role == "dialogue" then return end

    local hostile = IsHostileUnit(unit)
    if not hostile and not boss then return end
    if role == "add" and not CanAddBePullEvidence(npcId, boss) then return end

        local targetUnit = UnitTargetToken(unit)
    local targetGUID = UnitExists(targetUnit) and UnitGUID(targetUnit) or nil
    local previous = lastTargets[guid]
    lastTargets[guid] = {
        targetGUID = targetGUID,
        at = GetTime(),
    }
    if not targetGUID or not IsGroupTargetUnit(targetUnit) then return end

    if not UnitAffectingCombat(unit) and not AnyoneInCombat() then return end

    local pullerName, pullerGUID = ResolveOwner(targetUnit)
    local action = "锁定了"
    local evidence = source or "SCAN"
    local cast = recentCastByDest[guid]
    if cast and GetTime() - cast.at <= ACTION_LOOKUP_WINDOW
        and (not pullerName or cast.puller == pullerName) then
        action = "用 " .. cast.spell .. " 攻击了"
        evidence = "LOG_CAST"
        recentCastByDest[guid] = nil
    elseif previous and previous.targetGUID == targetGUID then
        evidence = source or "SCAN"
    end

    ReportPull({
        guid = guid,
        mobName = name,
        unit = unit,
        boss = boss,
        role = role or "trash",
        puller = pullerName,
        pullerGUID = pullerGUID,
        source = evidence,
        action = action,
        evidence = source or "SCAN",
    })
end

local function VerifyCastPull(pending)
    if not pending or reportedMobs[pending.guid] or deadMobs[pending.guid] then return end

    local opening = pending.npcId and OPENING_BY_ID[pending.npcId]
    if opening then
        return
    end

    local unit = pending.unit
    if not unit or not UnitExists(unit) or UnitGUID(unit) ~= pending.guid then
        unit = FindUnitForGUID(pending.guid)
    end
    if not unit then return end

    local targetUnit = unit .. "target"
    local targetIsGroup = UnitExists(targetUnit) and IsGroupTargetUnit(targetUnit)
    if not UnitAffectingCombat(unit) and not targetIsGroup then return end

    ReportPull({
        guid = pending.guid,
        mobName = pending.mobName,
        unit = unit,
        boss = pending.boss,
        role = pending.role,
        puller = pending.puller,
        pullerGUID = pending.pullerGUID,
        source = "LOG_CAST",
        action = (pending.evidence == "SPELL_AURA_APPLIED"
            or pending.evidence == "SPELL_AURA_APPLIED_DOSE")
            and ("用 " .. pending.spell .. " 触发了") or ("用 " .. pending.spell .. " 攻击了"),
        evidence = pending.evidence or "SPELL_CAST_SUCCESS",
    })
end

local function ScanForPulls()
    if not IsGroupType() then
        TrackNpcInteraction("player")
        return
    end
    scanRound = scanRound + 1
    local now = GetTime()

    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local ok, err = pcall(EvaluateNpcTarget, unit, "SCAN")
            if not ok then DebugPrint("nameplate 扫描失败: " .. tostring(err)) end
        end
    end

    pcall(EvaluateNpcTarget, "target", "SCAN")
    pcall(EvaluateNpcTarget, "focus", "SCAN")
    pcall(EvaluateNpcTarget, "mouseover", "SCAN")

    if scanRound % 2 == 0 then
        for _, unit in ipairs(groupUnits) do
            pcall(CheckSpecialTargetForUnit, unit)
            pcall(EvaluateNpcTarget, UnitTargetToken(unit), "SCAN")
        end
    else
        for _, unit in ipairs(groupUnits) do
            pcall(CheckSpecialTargetForUnit, unit)
        end
    end

    if scanRound % 4 == 0 then
        for i = 1, 5 do
            pcall(EvaluateNpcTarget, "boss" .. i, "SCAN")
        end
    end

    if scanRound % 25 == 0 then
        for guid, row in pairs(lastTargets) do
            if now - row.at > 120 then lastTargets[guid] = nil end
        end
        for guid, row in pairs(recentCastByDest) do
            if now - row.at > 3 then recentCastByDest[guid] = nil end
        end
        for guid, at in pairs(deadMobs) do
            if now - at > 900 then deadMobs[guid] = nil end
        end
        CleanupNpcInteractions(now)
        PruneSpecialCandidates()
    end
end

local function ScheduleScan(delay)
    if scanScheduled then return end
    scanScheduled = true
    After(delay or 0.05, function()
        scanScheduled = false
        ScanForPulls()
    end)
end

local function StartScan()
    if scanTicker then return end
    if C_Timer and C_Timer.NewTicker then
        scanTicker = C_Timer.NewTicker(SCAN_INTERVAL, function()
            ScanForPulls()
        end)
    end
end

local function StopScan()
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
end

local function UpdateScanState()
    StartScan()
end

local function ResetCombatState(reason)
    suppressCurrentCombat = false
    reportedMobs = {}
    dynamicAddBoss = {}
    lastTargets = {}
    recentCastByDest = {}
    specialCandidates = {}
    lastSpecialTargetByUnit = {}
    npcInteractions = {}
    lastFriendlyNpcTargetByUnit = {}
    reportedEncounterBosses = {}
    pendingCasts = {}
    petOwnerMap = {}
    summonMap = {}
    activeBossGUID = nil
    bossReported = false
    bossEngagedAt = nil
    initialAddReports = 0
    dialogueFallbackGeneration = dialogueFallbackGeneration + 1
    combatStartedAt = nil
    firstPullReported = false
    activeEncounter = nil
    WhoAdd.firstCombatPlayer = nil
    WhoAdd.firstCombatGUID = nil
    WhoAdd.firstCombatUnit = nil
    WhoAdd.firstCombatAt = nil
    BuildPetMap()
    DebugPrint("战斗状态重置: " .. tostring(reason))
end

local function ScheduleCombatReset()
    resetGeneration = resetGeneration + 1
    local generation = resetGeneration
    local function TryReset()
        if generation ~= resetGeneration then return end
        if AnyoneInCombat() then
            After(2, TryReset)
            return
        end
        ResetCombatState("out_of_combat")
    end
    After(2, TryReset)
end

local function HandleUnitTarget(unit)
    if not unit then return end
    if IsGroupUnit(unit) then
        CheckSpecialTargetForUnit(unit)
        EvaluateNpcTarget(UnitTargetToken(unit), "TARGET")
    else
        EvaluateNpcTarget(unit, "TARGET")
    end
end

local function HandleCombatLog()
    if not IsGroupType() then return end

    local timestamp, subevent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        spellId, spellName = CombatLogGetCurrentEventInfo()

    if not subevent then return end
    if subevent == "UNIT_DIED" then
        if destGUID and destFlags and bit.band(destFlags, OBJ_TYPE_NPC) > 0 then
            deadMobs[destGUID] = GetTime()
            dynamicAddBoss[destGUID] = nil
            if destGUID == activeBossGUID then
                activeBossGUID = nil
            end
        end
        return
    end

    if subevent == "SPELL_SUMMON" then
        if sourceGUID and destGUID then
            if IsGroupActor(sourceGUID, sourceName, sourceFlags) then
                local ownerName = ResolveOwnerByGUID(sourceGUID, sourceName)
                if ownerName then summonMap[destGUID] = ownerName end
            elseif sourceFlags and bit.band(sourceFlags, OBJ_TYPE_NPC) > 0 then
                local sourceBoss = GetPullInfo(sourceGUID, sourceName)
                if sourceBoss then dynamicAddBoss[destGUID] = sourceBoss end
            end
        end
        return
    end

    if not sourceFlags or not destFlags then return end

    local sourceIsNPC = bit.band(sourceFlags, OBJ_TYPE_NPC) > 0
    local sourceIsHostile = bit.band(sourceFlags, OBJ_REACTION_HOSTILE) > 0
    local destIsNPC = bit.band(destFlags, OBJ_TYPE_NPC) > 0
    local destIsGroup = IsGroupActor(destGUID, destName, destFlags)
    local sourceIsGroup = IsGroupActor(sourceGUID, sourceName, sourceFlags)

    -- 团队成员攻击 NPC
    if sourceIsGroup and destIsNPC then
        local boss, role, npcId = GetPullInfo(destGUID, destName)
        local dynamicBoss = not boss and dynamicAddBoss[destGUID] or nil
        if dynamicBoss then
            boss = dynamicBoss
            role = "add"
        end

        local puller, pullerGUID = ResolveOwnerByGUID(sourceGUID, sourceName)
        if role == "opening" or role == "dialogue" then
            return
        end

        if IsNonEngagingSpell(spellId, spellName) then return end

        local destIsHostile = bit.band(destFlags, OBJ_REACTION_HOSTILE) > 0
        if boss or destIsHostile then
            if ATTACK_EVENTS[subevent] then
                local action
                if subevent == "SWING_DAMAGE" then
                    action = "用普通攻击攻击了"
                elseif spellName and spellName ~= "" then
                    action = "用 " .. spellName .. " 攻击了"
                else
                    action = "攻击了"
                end
                ReportPull({
                    guid = destGUID,
                    mobName = destName,
                    unit = FindUnitForGUID(destGUID),
                    boss = boss,
                    role = role or "trash",
                    puller = puller,
                    pullerGUID = pullerGUID,
                    source = "LOG_FWD",
                    action = action,
                    evidence = subevent,
                })
            elseif subevent == "SPELL_CAST_START" or subevent == "SPELL_CAST_SUCCESS"
                or subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_APPLIED_DOSE" then
                if spellName then
                    recentCastByDest[destGUID] = {
                        spell = spellName,
                        puller = puller,
                        at = GetTime(),
                    }
                end
                if subevent ~= "SPELL_CAST_START" then
                    local pending = {
                        guid = destGUID,
                        mobName = destName,
                        unit = FindUnitForGUID(destGUID),
                        boss = boss,
                        role = role or "trash",
                        puller = puller,
                        pullerGUID = pullerGUID,
                        spell = spellName or "未知技能",
                        npcId = npcId,
                        evidence = subevent,
                    }
                    pendingCasts[#pendingCasts + 1] = pending
                    if #pendingCasts > 80 then table.remove(pendingCasts, 1) end
                    After(0.45, function()
                        VerifyCastPull(pending)
                    end)
                end
            end
        end
        return
    end

    -- NPC 反击团队成员
    if sourceIsNPC and sourceIsHostile and destIsGroup and NPC_DAMAGE_EVENTS[subevent] then
        local boss, role = GetPullInfo(sourceGUID, sourceName)
        if not boss then boss = dynamicAddBoss[sourceGUID] end
        local puller, pullerGUID = ResolveOwnerByGUID(destGUID, destName)
        local action
        if sourceName then
            action = "被 " .. sourceName .. " 攻击（走近引怪）"
        else
            action = "被怪物攻击（走近引怪）"
        end
        ReportPull({
            guid = sourceGUID,
            mobName = sourceName,
            unit = FindUnitForGUID(sourceGUID),
            boss = boss,
            role = boss and (role or "boss") or "trash",
            puller = puller,
            pullerGUID = pullerGUID,
            source = "LOG_REV",
            action = action,
            evidence = subevent,
        })
    end
end

-- ============================================================
-- 主界面
-- ============================================================

local function BuildMainUI()
listFrame = CreateFrame("Frame", "WhoAddListFrame", UIParent)
listFrame:SetSize(940, 640)
listFrame:SetPoint("CENTER")
listFrame:SetFrameStrata("DIALOG")
listFrame:SetMovable(true)
listFrame:EnableMouse(true)
listFrame:SetClampedToScreen(true)
UI.ApplyCard(listFrame, UI.colors.bg, UI.colors.border, 8)
listFrame:RegisterForDrag("LeftButton")
listFrame:SetScript("OnDragStart", listFrame.StartMoving)
listFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if type(WhoAddDB) ~= "table" then WhoAddDB = {} end
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint(1)
    WhoAddDB.window = {
        point = point or "CENTER",
        relativePoint = relativePoint or point or "CENTER",
        x = xOfs or 0,
        y = yOfs or 0,
    }
    PersistToDisk()
end)
listFrame:Hide()

do
    local brandMark = listFrame:CreateTexture(nil, "ARTWORK")
    brandMark:SetTexture("Interface\\AddOns\\WhoAdd\\Media\\WhoAddIcon")
    brandMark:SetSize(26, 26)
    brandMark:SetPoint("TOPLEFT", 22, -15)

    local title = UI.Label(listFrame, "WhoAdd", "GameFontNormalLarge", UI.colors.text)
    title:SetPoint("LEFT", brandMark, "RIGHT", 8, 0)

    local versionLabel = UI.Label(listFrame, "v" .. WhoAddVersion, "GameFontNormalSmall", UI.colors.textDim)
    versionLabel:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local subtitle = UI.Label(listFrame, "开怪取证 · 全团快照 · 最近 3 天记录",
        "GameFontNormalSmall", UI.colors.textDim)
    subtitle:SetPoint("TOPLEFT", 22, -45)

    local closeButton = UI.Button(listFrame, "×", 32, 30, "ghost")
    closeButton:SetPoint("TOPRIGHT", -16, -14)
    closeButton:SetScript("OnClick", function() listFrame:Hide() end)

    local headerDivider = UI.Divider(listFrame)
    headerDivider:SetPoint("TOPLEFT", 18, -66)
    headerDivider:SetPoint("TOPRIGHT", -18, -66)
end

local tabButtons = {}
local tabUnderlines = {}
local pages = {}
local tabDefs = {
    { key = "records", text = "引怪记录" },
    { key = "settings", text = "设置" },
    { key = "bosses", text = "Boss 资料" },
}

for index, tabDef in ipairs(tabDefs) do
    local button = UI.Button(listFrame, tabDef.text, 126, 32, "secondary")
    if index == 1 then
        button:SetPoint("TOPLEFT", 20, -79)
    else
        button:SetPoint("LEFT", tabButtons[index - 1], "RIGHT", 6, 0)
    end
    button:SetScript("OnClick", function()
        SelectTab(index)
    end)
    tabButtons[index] = button

    local underline = button:CreateTexture(nil, "OVERLAY")
    underline:SetPoint("BOTTOM", 0, 2)
    underline:SetWidth(18)
    underline:SetHeight(2)
    underline:SetTexture(UI.ROUNDED_TEXTURE)
    underline:SetVertexColor(UI.colors.accent[1], UI.colors.accent[2], UI.colors.accent[3], 1)
    underline:Hide()
    tabUnderlines[index] = underline

    local page = CreateFrame("Frame", nil, listFrame)
    page:SetPoint("TOPLEFT", 20, -122)
    page:SetPoint("BOTTOMRIGHT", -20, 20)
    page:Hide()
    pages[index] = page
end

-- 记录页
do
local recordsPage = pages[1]

local recordsHint = UI.Label(recordsPage, "记录保留最近 3 天，点击任意记录查看对应开怪快照",
    "GameFontNormalSmall", UI.colors.textDim)
recordsHint:SetPoint("TOPLEFT", 2, -4)

local clearBtn = UI.Button(recordsPage, "清空记录", 82, 28, "danger")
clearBtn:SetPoint("TOPRIGHT", 0, 0)
clearBtn:SetText("清空记录")
clearBtn:SetScript("OnClick", function()
    if UI.ShowConfirm then
        UI.ShowConfirm("清空引怪记录",
            "确定清空全部 WhoAdd 引怪记录与快照吗？此操作不可恢复。",
            "清空", function()
                if ClearRecords then ClearRecords() end
            end, true)
    elseif StaticPopup_Show then
        StaticPopup_Show("WHOADD_CLEAR_RECORDS")
    elseif ClearRecords then
        ClearRecords()
    end
end)

local nextPageBtn = UI.Button(recordsPage, ">", 30, 28, "secondary")
nextPageBtn:SetPoint("TOPRIGHT", clearBtn, "TOPLEFT", -6, 0)

local recordPageLabel = UI.Label(recordsPage, "第 1 / 1 页 · 0 条", "GameFontNormalSmall", UI.colors.textDim, 140)
recordPageLabel:SetPoint("RIGHT", nextPageBtn, "LEFT", -8, 0)
recordPageLabel:SetJustifyH("RIGHT")
recordPageLabel:SetText("第 1 / 1 页 · 0 条")

local prevPageBtn = UI.Button(recordsPage, "<", 30, 28, "secondary")
prevPageBtn:SetPoint("RIGHT", recordPageLabel, "LEFT", -8, 0)

local function GoRecordPage(delta)
    local totalPages = math.max(1, math.ceil(#pullLog / RECORDS_PER_PAGE))
    currentRecordPage = math.max(1, math.min(totalPages, currentRecordPage + (delta or 0)))
    local firstIndex = (currentRecordPage - 1) * RECORDS_PER_PAGE + 1
    selectedRecord = pullLog[firstIndex]
    if RefreshRecordList then RefreshRecordList() end
end

prevPageBtn:SetScript("OnClick", function()
    GoRecordPage(-1)
end)

nextPageBtn:SetScript("OnClick", function()
    GoRecordPage(1)
end)

local listCard = UI.CreateCard(recordsPage, UI.colors.panel, UI.colors.border)
listCard:SetPoint("TOPLEFT", 0, -38)
listCard:SetPoint("BOTTOMLEFT", 0, 0)
listCard:SetWidth(330)

do
    local title = UI.Label(listCard, "引怪记录", "GameFontNormalLarge", UI.colors.accent)
    title:SetPoint("TOPLEFT", 14, -13)

    local subtitle = UI.Label(listCard, "PULL TIMELINE", "GameFontNormalSmall", UI.colors.textDim)
    subtitle:SetPoint("TOPLEFT", 14, -34)
end

local recordScroll = UI.CreateScroll(listCard, "WhoAddRecordScroll")
recordScroll:SetPoint("TOPLEFT", 10, -50)
recordScroll:SetPoint("BOTTOMRIGHT", -16, -10)

local recordContent = CreateFrame("Frame", nil, recordScroll)
recordContent:SetSize(294, 1)
recordScroll:SetScrollChild(recordContent)

local recordEmpty = UI.Label(recordContent, "暂无引怪记录\n开怪后，全团快照会显示在这里",
    "GameFontNormalSmall", UI.colors.textDim, 260)
recordEmpty:SetPoint("TOP", 0, -36)
recordEmpty:SetJustifyH("CENTER")

local detailFrame = UI.CreateCard(recordsPage, UI.colors.panel, UI.colors.border)
detailFrame:SetPoint("TOPLEFT", listCard, "TOPRIGHT", 12, 0)
detailFrame:SetPoint("BOTTOMRIGHT", 0, 0)

do
    local title = UI.Label(detailFrame, "快照详情", "GameFontNormalLarge", UI.colors.accent)
    title:SetPoint("TOPLEFT", 14, -13)

    local subtitle = UI.Label(detailFrame, "职责、位置、目标、施法与距怪信息", "GameFontNormalSmall", UI.colors.textDim)
    subtitle:SetPoint("TOPLEFT", 14, -34)
end

local detailScroll = UI.CreateScroll(detailFrame, "WhoAddDetailScroll")
detailScroll:SetPoint("TOPLEFT", 14, -50)
detailScroll:SetPoint("BOTTOMRIGHT", -18, -10)

local detailContent = CreateFrame("Frame", nil, detailScroll)
detailContent:SetSize(500, 1)
detailScroll:SetScrollChild(detailContent)

local detailText = UI.Label(detailContent, "选择左侧记录查看快照。", "ChatFontNormal", UI.colors.text)
detailText:SetPoint("TOPLEFT", 4, -4)
detailText:SetWidth(500)
detailText:SetJustifyH("LEFT")
detailText:SetWordWrap(true)
detailText:SetText(UI.hex.dim .. "选择左侧记录查看快照。|r")

local function FormatPlayerLine(player)
    local role = ROLE_LABELS[player.role or "NONE"] or "未分配"
    local roleColor = player.role == "TANK" and "|cff42a5f5"
        or player.role == "HEALER" and "|cff4caf50"
        or (player.role == "DAMAGER" or player.role == "DPS") and "|cffff9800"
        or "|cff9eacbb"
    local nameColor = ClassColor(player.classFile)
    local healthColor = player.healthPct < 35 and "|cffff4444"
        or player.healthPct < 70 and "|cffffff66"
        or "|cff4caf50"
    local distance = player.distance and string.format("%.1f码", player.distance) or "?"
    local status
    if player.dead then
        status = "|cffff4444阵亡|r"
    elseif player.connected == false then
        status = "|cff888888离线|r"
    else
        status = "在线"
    end

    local target = player.targetName or "无"
    if player.targetType then
        target = target .. "|cff888888[" .. player.targetType .. "]|r"
    end
    local cast = "无"
    if player.cast then
        cast = string.format("%s: %s %.1fs", player.cast.kind, player.cast.name, player.cast.remaining or 0)
    end
    local pos = player.position and string.format("%.1f, %.1f", player.position.x, player.position.y) or "未知"

    local line1 = string.format("%s[%s]|r %s%s|r  %s%s%%|r  |cff9eacbb%s|r  |cff9eacbb距怪 %s|r",
        roleColor, role, nameColor, player.name,
        healthColor, math.floor(player.healthPct + 0.5), status, distance)
    local line2 = string.format("      |cff718096目标:|r %s  |cff718096%s|r  |cff718096坐标:|r %s",
        target, cast, pos)
    return line1, line2
end

local function BuildRecordDetail(record)
    if not record then
        return UI.hex.dim .. "选择左侧记录查看快照。|r"
    end

    local lines = {}
    lines[#lines + 1] = string.format("%s#%d|r  %s%s|r  %s%s|r",
        UI.hex.accent, record.id, UI.hex.text,
        record.mobDisplayName or record.mobName or "未知",
        UI.hex.dim, record.dateText or record.timeText or "")
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("%s引怪者|r  %s%s|r    %s类型|r  %s%s|r",
        UI.hex.accent, UI.hex.text, record.puller or "未知",
        UI.hex.accent, UI.hex.text, record.typeLabel or "未知")
    if record.bossName then
        lines[#lines + 1] = string.format("%s首领|r  %s%s|r    %s副本|r  %s%s|r",
            UI.hex.accent, UI.hex.text, record.bossName,
            UI.hex.accent, UI.hex.text, record.raid or "未知")
    else
        lines[#lines + 1] = string.format("%s区域|r  %s%s|r",
            UI.hex.accent, UI.hex.text, record.raid or "未知")
    end
    lines[#lines + 1] = string.format("%s证据|r  %s%s|r    %s动作|r  %s%s|r",
        UI.hex.accent, UI.hex.text, record.sourceLabel or record.source or "未知",
        UI.hex.accent, UI.hex.text, record.action or "未知")
    if record.triggerMobName and record.triggerMobName ~= "" then
        lines[#lines + 1] = string.format("%s触发目标|r  %s%s|r",
            UI.hex.accent, UI.hex.text, record.triggerMobName)
    end
    if record.npcID then
        lines[#lines + 1] = string.format("%sNPC ID|r  %s%s|r",
            UI.hex.accent, UI.hex.text, tostring(record.npcID))
    end
    if record.encounter and record.encounter.name then
        lines[#lines + 1] = string.format("%s遭遇战|r  %s%s|r    %sEncounter ID|r  %s%s|r",
            UI.hex.accent, UI.hex.text, record.encounter.name,
            UI.hex.accent, UI.hex.text, tostring(record.encounter.id or "?"))
    end
    if record.distance then
        lines[#lines + 1] = string.format("%s引怪者距怪|r  %s%.1f 码|r",
            UI.hex.accent, UI.hex.text, record.distance)
    else
        lines[#lines + 1] = UI.hex.accent .. "引怪者距怪|r  " .. UI.hex.dim .. "未知|r"
    end
    if record.message then
        lines[#lines + 1] = UI.hex.accent .. "通报文本|r"
        lines[#lines + 1] = record.message
    end
    if record.npcClickerText and record.npcClickerText ~= "" then
        lines[#lines + 1] = UI.hex.accent .. "对话开怪者|r"
        lines[#lines + 1] = string.gsub(record.npcClickerText, "、", "\n")
    end
    lines[#lines + 1] = ""

    local snapshot = record.snapshot
    if not snapshot or not snapshot.players or #snapshot.players == 0 then
        lines[#lines + 1] = UI.hex.warning .. "快照采集失败或当时没有团队成员数据。|r"
        return table.concat(lines, "\n")
    end

    lines[#lines + 1] = string.format("%s全团快照|r  %s%d 人 · %s|r",
        UI.hex.accent, UI.hex.dim,
        #snapshot.players, snapshot.zone or record.raid or "未知区域")
    if snapshot.mob and snapshot.mob.position then
        lines[#lines + 1] = string.format("%s怪物坐标: %.1f, %.1f|r", UI.hex.dim,
            snapshot.mob.position.x, snapshot.mob.position.y)
    end
    lines[#lines + 1] = UI.hex.dim .. "职责 / 玩家 / 血量 / 状态 / 距怪；第二行为目标、施法/引导和坐标。|r"
    lines[#lines + 1] = ""

    for _, player in ipairs(snapshot.players) do
        local line1, line2 = FormatPlayerLine(player)
        lines[#lines + 1] = line1
        lines[#lines + 1] = line2
    end
    return table.concat(lines, "\n")
end

ShowRecordDetail = function(record)
    detailText:SetText(BuildRecordDetail(record))
    local height = math.max(360, detailText:GetStringHeight() + 30)
    detailContent:SetHeight(height)
    detailScroll:SetVerticalScroll(0)
    if detailScroll.UpdateScrollRange then detailScroll.UpdateScrollRange() end
end

UpdateRecordSelection = function()
    for _, row in ipairs(recordRows) do
        if row:IsShown() then
            local selected = row.record == selectedRecord
            row.accent:SetShown(selected)
            UI.AnimateVisual(row,
                selected and UI.colors.panelHover or UI.colors.panelAlt,
                selected and UI.colors.accent or UI.colors.border, 0.16)
        end
    end
end

SelectRecord = function(record)
    selectedRecord = record
    ShowRecordDetail(record)
    UpdateRecordSelection()
end

RefreshRecordList = function()
    for _, row in ipairs(recordRows) do row:Hide() end
    local total = #pullLog
    local totalPages = math.max(1, math.ceil(total / RECORDS_PER_PAGE))
    currentRecordPage = math.max(1, math.min(totalPages, currentRecordPage))
    prevPageBtn:SetEnabled(currentRecordPage > 1)
    nextPageBtn:SetEnabled(currentRecordPage < totalPages)
    prevPageBtn:SetAlpha(currentRecordPage > 1 and 1 or 0.45)
    nextPageBtn:SetAlpha(currentRecordPage < totalPages and 1 or 0.45)
    recordPageLabel:SetText(string.format("第 %d / %d 页 · 共 %d 条",
        total > 0 and currentRecordPage or 0, total > 0 and totalPages or 0, total))
    recordEmpty:SetShown(total == 0)

    if total == 0 then
        selectedRecord = nil
        recordContent:SetHeight(150)
        ShowRecordDetail(nil)
        if recordScroll.UpdateScrollRange then recordScroll.UpdateScrollRange() end
        return
    end

    local startIndex = (currentRecordPage - 1) * RECORDS_PER_PAGE + 1
    local endIndex = math.min(total, startIndex + RECORDS_PER_PAGE - 1)
    local rowHeight = 54
    for recordIndex = startIndex, endIndex do
        local slot = recordIndex - startIndex + 1
        local record = pullLog[recordIndex]
        local row = recordRows[slot]
        if not row then
            row = CreateFrame("Button", nil, recordContent)
            row:SetSize(278, 48)
            row:SetPoint("TOPLEFT", 4, -((slot - 1) * rowHeight + 4))
            UI.ApplyCard(row, UI.colors.panelAlt, UI.colors.border, 8)

            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetPoint("TOPLEFT", 3, -5)
            row.accent:SetPoint("BOTTOMLEFT", 3, 5)
            row.accent:SetWidth(3)
            SetSolidColor(row.accent, UI.colors.accent[1], UI.colors.accent[2], UI.colors.accent[3], 1)
            row.accent:Hide()

            row.label = row:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
            row.label:SetPoint("TOPLEFT", 12, -6)
            row.label:SetWidth(254)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(true)

            row:SetScript("OnEnter", function(self)
                if self.record ~= selectedRecord then
                    UI.AnimateVisual(self, UI.colors.panelHover, UI.colors.accent, 0.14)
                end
            end)
            row:SetScript("OnLeave", function(self)
                if self.record ~= selectedRecord then
                    UI.AnimateVisual(self, UI.colors.panelAlt, UI.colors.border, 0.16)
                end
            end)
            row:SetScript("OnMouseDown", function(self) self:SetScale(0.992) end)
            row:SetScript("OnMouseUp", function(self) self:SetScale(1) end)
            recordRows[slot] = row
        end

        row.record = record
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, -((slot - 1) * rowHeight + 4))
        local color = record.bossRelated and UI.hex.accent or UI.hex.warning
        row.label:SetText(string.format("%s#%d|r  %s%s|r\n%s%s|r    %s%s|r",
            UI.hex.accent, record.id, UI.hex.text,
            record.mobDisplayName or record.mobName or "未知",
            UI.hex.dim, record.timeText or "未知时间",
            color, record.typeLabel or "怪物"))
        row:SetScript("OnClick", function()
            SelectRecord(record)
        end)
        row:Show()
    end

    recordContent:SetHeight(math.max((endIndex - startIndex + 1) * rowHeight + 8, 30))
    if recordScroll.UpdateScrollRange then recordScroll.UpdateScrollRange() end
    if not selectedRecord or not selectedRecord.mobGUID then
        selectedRecord = pullLog[startIndex]
    end
    ShowRecordDetail(selectedRecord)
    UpdateRecordSelection()
end

function WhoAddListFrame_Refresh()
    if RefreshRecordList then RefreshRecordList() end
end

ClearRecords = function()
    pullLog = {}
    selectedRecord = nil
    nextPullID = 1
    currentRecordPage = 1
    SaveHistory()
    PersistToDisk()
    pendingAnnouncements.items = {}
    pendingAnnouncements.readyAt = 0
    pendingAnnouncements.waitingCombat = false
    RefreshRecordList()
end
end

ResetWhoAddSettings = function()
    settings.reportMode = "boss"
    settings.templateLead = DEFAULT_TEMPLATE_LEAD
    settings.templateSuffix = ""
    settings.templateTokens = CopyTemplateTokens(DEFAULT_TEMPLATE_TOKENS)
    settings.templateSeparators = nil
    settings.template = BuildTemplateFromTokens(settings.templateTokens,
        settings.templateLead, settings.templateSuffix)
    settings.delayOutOfCombat = false
    settings.delaySeconds = 3
    settings.textEnabled = true
    settings.soundEnabled = true
    settings.soundKit = DEFAULT_SOUND_KIT
    settings.popupEnabled = true
    settings.includeDistance = true
    if type(WhoAddDB.minimap) ~= "table" then WhoAddDB.minimap = {} end
    WhoAddDB.minimap.minimapPos = 225
    WhoAddDB.minimap.hide = false
    if WhoAdd.RefreshMinimapIcon then WhoAdd.RefreshMinimapIcon() end
    pendingAnnouncements.items = {}
    pendingAnnouncements.readyAt = 0
    pendingAnnouncements.waitingCombat = false
    if SyncSettingsUI then SyncSettingsUI() end
    SaveSettings()
end

if StaticPopupDialogs then
    StaticPopupDialogs["WHOADD_CLEAR_RECORDS"] = {
        text = "确定清空全部 WhoAdd 引怪记录与快照吗？此操作不可恢复。",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            if ClearRecords then ClearRecords() end
        end,
    }
    StaticPopupDialogs["WHOADD_RESET_SETTINGS"] = {
        text = "恢复 WhoAdd 的默认设置？",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            if ResetWhoAddSettings then ResetWhoAddSettings() end
        end,
    }
end

-- 设置页
do
local settingsPage = pages[2]

local settingsLeftCard = UI.CreateCard(settingsPage, UI.colors.panel, UI.colors.border)
settingsLeftCard:SetPoint("TOPLEFT", 0, 0)
settingsLeftCard:SetPoint("BOTTOMLEFT", 0, 0)
settingsLeftCard:SetWidth(480)

local settingsRightCard = UI.CreateCard(settingsPage, UI.colors.panel, UI.colors.border)
settingsRightCard:SetPoint("TOPLEFT", settingsLeftCard, "TOPRIGHT", 12, 0)
settingsRightCard:SetPoint("BOTTOMRIGHT", 0, 0)

local function CreateSettingLabel(parent, text, x, y, template)
    local label = UI.Label(parent, text, template or "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    return label
end

local function CreateSettingCheck(parent, text, x, y, onClick, width)
    local check = UI.Checkbox(parent, text, width or 360, onClick)
    check:SetPoint("TOPLEFT", x, y)
    return check
end

do
    local leftTitle = UI.Label(settingsLeftCard, "通报行为", "GameFontNormalLarge", UI.colors.accent)
    leftTitle:SetPoint("TOPLEFT", 16, -14)
    local leftSubtitle = UI.Label(settingsLeftCard, "范围、自定义文本与延迟规则", "GameFontNormalSmall", UI.colors.textDim)
    leftSubtitle:SetPoint("TOPLEFT", 16, -35)
    local leftDivider = UI.Divider(settingsLeftCard)
    leftDivider:SetPoint("TOPLEFT", 16, -56)
    leftDivider:SetPoint("TOPRIGHT", -16, -56)
end

CreateSettingLabel(settingsLeftCard, "通报范围", 16, -70)

reportModeLabels = {
    all = "通报所有",
    boss = "仅通报团队 Boss",
    none = "不通报",
}

SetReportMode = function(mode)
    if mode ~= "all" and mode ~= "boss" and mode ~= "none" then return end
    if mode ~= settings.reportMode then
        pendingAnnouncements.items = {}
        pendingAnnouncements.readyAt = 0
        pendingAnnouncements.waitingCombat = false
    end
    settings.reportMode = mode
    if modeButton then
        modeButton:SetText("当前：" .. reportModeLabels[mode] .. "（点击切换）")
        modeButton:SetSelected(true)
    end
    SaveSettings()
end

modeButton = UI.Button(settingsLeftCard, "", 448, 30, "secondary")
modeButton:SetPoint("TOPLEFT", 16, -90)
modeButton:SetText("当前：" .. (reportModeLabels[settings.reportMode] or "仅通报团队 Boss") .. "（点击切换）")
modeButton:SetSelected(true)
modeButton:SetScript("OnClick", function()
    if settings.reportMode == "all" then
        SetReportMode("boss")
    elseif settings.reportMode == "boss" then
        SetReportMode("none")
    else
        SetReportMode("all")
    end
end)

CreateSettingLabel(settingsLeftCard, "文字通报模板", 16, -136)

local templatePreviewCard = UI.CreateCard(settingsLeftCard, UI.colors.panelAlt, UI.colors.border, 4)
templatePreviewCard:SetPoint("TOPLEFT", 16, -158)
templatePreviewCard:SetSize(448, 86)

local templatePreviewText = UI.Label(templatePreviewCard, "", "ChatFontNormal", UI.colors.text, 424)
templatePreviewText:SetPoint("TOPLEFT", 12, -9)
templatePreviewText:SetJustifyH("LEFT")
templatePreviewText:SetWordWrap(true)

local templatePreviewHint = UI.Label(templatePreviewCard, "", "GameFontNormalSmall", UI.colors.textDim, 424)
templatePreviewHint:SetPoint("BOTTOMLEFT", 12, 7)
templatePreviewHint:SetJustifyH("LEFT")

local templateEditButton = UI.Button(settingsLeftCard, "勾选并拖动占位符", 272, 30, "primary")
templateEditButton:SetPoint("TOPLEFT", 16, -252)
templateEditButton:SetText("勾选并拖动占位符")
templateEditButton:SetScript("OnClick", function()
    if OpenTemplateEditor then OpenTemplateEditor() end
end)

local recommendedTemplateButton = UI.Button(settingsLeftCard, "恢复推荐模板", 168, 30, "secondary")
recommendedTemplateButton:SetPoint("LEFT", templateEditButton, "RIGHT", 8, 0)
recommendedTemplateButton:SetText("恢复推荐模板")
recommendedTemplateButton:SetScript("OnClick", function()
    settings.templateLead = DEFAULT_TEMPLATE_LEAD
    settings.templateSuffix = ""
    settings.templateTokens = CopyTemplateTokens(DEFAULT_TEMPLATE_TOKENS)
    settings.templateSeparators = nil
    settings.template = BuildTemplateFromTokens(settings.templateTokens,
        settings.templateLead, settings.templateSuffix)
    if SyncTemplateBuilderUI then SyncTemplateBuilderUI() end
    SaveSettings()
end)

local templateSampleRecord = {
    puller = "示例开怪者",
    npcClickerChat = "示例对话者@21:03:12（3.5秒）",
    mobDisplayName = "血领主曼多基尔",
    mobName = "血领主曼多基尔",
    bossName = "血领主曼多基尔",
    raid = "祖尔格拉布",
    action = "用 英勇打击 攻击了",
    timeText = "21:03:15",
    sourceLabel = "战斗日志",
    npcID = 14988,
    distance = 18.6,
    snapshot = { players = {} },
}
for index = 1, 25 do templateSampleRecord.snapshot.players[index] = {} end

local templateCheckboxes = {}
local templateChips = {}
local templateEditor
local templateEditorCard
local templateEditorSampleText
local templateEditorStructureText
local templateEditorStatusText
local templateOrderCard
local SetTokenSelected
local LayoutSelectedChips
local RefreshTemplateEditor

local function RefreshTemplatePreview()
    settings.template = BuildTemplateFromTokens(settings.templateTokens,
        settings.templateLead, settings.templateSuffix, settings.templateSeparators)
    if templatePreviewText then
        local rendered = RenderTemplate(templateSampleRecord, settings.template)
        if rendered == "" then rendered = "（当前模板不会输出文字）" end
        templatePreviewText:SetText(rendered)
    end
    if templatePreviewHint then
        templatePreviewHint:SetText(string.format("已选 %d 个占位符 · 点击上方按钮可视化编辑",
            #settings.templateTokens))
    end
    if templateEditorSampleText then
        local rendered = RenderTemplate(templateSampleRecord, settings.template)
        if rendered == "" then rendered = "（当前模板不会输出文字）" end
        templateEditorSampleText:SetText(rendered)
    end
    if templateEditorStructureText then
        local labels = {}
        if settings.templateLead and settings.templateLead ~= "" then
            labels[#labels + 1] = settings.templateLead:gsub("%s+$", "")
        end
        for index, key in ipairs(settings.templateTokens) do
            labels[#labels + 1] = string.format("%d.%s", index, TEMPLATE_TOKEN_LABELS[key] or key)
        end
        local structure = #labels > 0 and table.concat(labels, "  →  ")
            or "尚未选择占位符"
        templateEditorStructureText:SetText("当前结构：" .. structure)
    end
    if templateEditorStatusText then
        templateEditorStatusText:SetText(string.format(
            "已选 %d / %d · 勾选后会自动保存，按住已选标签拖动即可排序",
            #settings.templateTokens, #TEMPLATE_TOKEN_DEFS))
    end
end

templateEditor = CreateFrame("Frame", "WhoAddTemplateEditor", UIParent)
templateEditor:SetAllPoints(UIParent)
templateEditor:SetFrameStrata("FULLSCREEN_DIALOG")
templateEditor:SetToplevel(true)
templateEditor:EnableMouse(true)
templateEditor:Hide()

local templateEditorShade = templateEditor:CreateTexture(nil, "BACKGROUND")
templateEditorShade:SetAllPoints()
SetSolidColor(templateEditorShade, 0.015, 0.025, 0.040, 0.68)

templateEditorCard = UI.CreateCard(templateEditor, UI.colors.panel, UI.colors.border, 8)
templateEditorCard:SetSize(780, 580)
templateEditorCard:SetPoint("CENTER")

local templateEditorIcon = templateEditorCard:CreateTexture(nil, "ARTWORK")
templateEditorIcon:SetTexture("Interface\\AddOns\\WhoAdd\\Media\\WhoAddIcon")
templateEditorIcon:SetSize(24, 24)
templateEditorIcon:SetPoint("TOPLEFT", 18, -16)

local templateEditorTitle = UI.Label(templateEditorCard, "文字通报模板构建器",
    "GameFontNormalLarge", UI.colors.accent)
templateEditorTitle:SetPoint("LEFT", templateEditorIcon, "RIGHT", 10, 0)

local templateEditorSubtitle = UI.Label(templateEditorCard,
    "先勾选需要的占位符，再拖动已选标签调整通报顺序；示例会实时更新",
    "GameFontNormalSmall", UI.colors.textDim)
templateEditorSubtitle:SetPoint("TOPLEFT", 54, -45)

local templateEditorClose = UI.Button(templateEditorCard, "×", 32, 30, "ghost")
templateEditorClose:SetPoint("TOPRIGHT", -16, -14)

local templateEditorDivider = UI.Divider(templateEditorCard)
templateEditorDivider:SetPoint("TOPLEFT", 18, -66)
templateEditorDivider:SetPoint("TOPRIGHT", -18, -66)

local availableTokenCard = UI.CreateCard(templateEditorCard, UI.colors.panelAlt, UI.colors.border, 6)
availableTokenCard:SetPoint("TOPLEFT", 18, -80)
availableTokenCard:SetSize(374, 228)

local availableTokenTitle = UI.Label(availableTokenCard, "可用占位符",
    "GameFontNormal", UI.colors.text)
availableTokenTitle:SetPoint("TOPLEFT", 14, -12)
local availableTokenHint = UI.Label(availableTokenCard, "勾选后加入右侧顺序",
    "GameFontNormalSmall", UI.colors.textDim)
availableTokenHint:SetPoint("TOPRIGHT", -14, -13)

templateOrderCard = UI.CreateCard(templateEditorCard, UI.colors.panelAlt, UI.colors.border, 6)
templateOrderCard:SetPoint("TOPRIGHT", -18, -80)
templateOrderCard:SetSize(374, 228)

local orderTitle = UI.Label(templateOrderCard, "通报顺序", "GameFontNormal", UI.colors.text)
orderTitle:SetPoint("TOPLEFT", 14, -12)
local orderHint = UI.Label(templateOrderCard, "按住标签拖动排序",
    "GameFontNormalSmall", UI.colors.accent)
orderHint:SetPoint("TOPRIGHT", -14, -13)

local templateSampleCard = UI.CreateCard(templateEditorCard,
    UI.colors.panelAlt, UI.colors.border, 6)
templateSampleCard:SetPoint("TOPLEFT", 18, -318)
templateSampleCard:SetSize(744, 148)

local sampleTitle = UI.Label(templateSampleCard, "实时示例",
    "GameFontNormal", UI.colors.text)
sampleTitle:SetPoint("TOPLEFT", 14, -12)
local sampleHint = UI.Label(templateSampleCard, "使用当前勾选、顺序和距离开关模拟输出",
    "GameFontNormalSmall", UI.colors.textDim)
sampleHint:SetPoint("TOPRIGHT", -14, -13)

local sampleOutputCard = UI.CreateCard(templateSampleCard,
    UI.colors.panel, UI.colors.border, 4)
sampleOutputCard:SetPoint("TOPLEFT", 14, -36)
sampleOutputCard:SetSize(716, 68)

templateEditorSampleText = UI.Label(sampleOutputCard, "",
    "ChatFontNormal", UI.colors.text, 690)
templateEditorSampleText:SetPoint("TOPLEFT", 12, -10)
templateEditorSampleText:SetJustifyH("LEFT")
templateEditorSampleText:SetWordWrap(true)

templateEditorStructureText = UI.Label(templateSampleCard, "",
    "GameFontNormalSmall", UI.colors.textDim, 716)
templateEditorStructureText:SetPoint("TOPLEFT", 14, -112)
templateEditorStructureText:SetJustifyH("LEFT")

templateEditorStatusText = UI.Label(templateEditorCard, "",
    "GameFontNormalSmall", UI.colors.textDim, 470)
templateEditorStatusText:SetPoint("TOPLEFT", 18, -476)
templateEditorStatusText:SetJustifyH("LEFT")

local templateEditorFooterDivider = UI.Divider(templateEditorCard)
templateEditorFooterDivider:SetPoint("TOPLEFT", 18, -500)
templateEditorFooterDivider:SetPoint("TOPRIGHT", -18, -500)

local clearTemplateButton = UI.Button(templateEditorCard, "清空占位符", 108, 30, "secondary")
clearTemplateButton:SetPoint("BOTTOMLEFT", 18, 16)
clearTemplateButton:SetText("清空占位符")

local recommendTemplateButton = UI.Button(templateEditorCard, "推荐顺序", 108, 30, "secondary")
recommendTemplateButton:SetPoint("LEFT", clearTemplateButton, "RIGHT", 8, 0)
recommendTemplateButton:SetText("推荐顺序")

local doneTemplateButton = UI.Button(templateEditorCard, "完成", 96, 30, "primary")
doneTemplateButton:SetPoint("BOTTOMRIGHT", -18, 16)
doneTemplateButton:SetText("完成")

local function ApplyTemplateChange(animateKey)
    settings.templateTokens = NormalizeTemplateTokens(settings.templateTokens)
    settings.templateSeparators = nil
    settings.template = BuildTemplateFromTokens(settings.templateTokens,
        settings.templateLead, settings.templateSuffix)
    RefreshTemplateEditor(animateKey)
    SaveSettings()
end

SetTokenSelected = function(key, selected)
    local tokens = settings.templateTokens
    local existing
    for index, tokenKey in ipairs(tokens) do
        if tokenKey == key then existing = index break end
    end
    if selected and not existing then
        tokens[#tokens + 1] = key
    elseif not selected and existing then
        table.remove(tokens, existing)
    else
        return
    end
    ApplyTemplateChange(selected and key or nil)
end

local function FindNearestTokenSlot(frame)
    local left, top = templateOrderCard:GetLeft(), templateOrderCard:GetTop()
    if not left or not top then return 0 end
    local centerX = (frame:GetLeft() + frame:GetRight()) / 2
    local centerY = (frame:GetTop() + frame:GetBottom()) / 2
    local bestIndex = 0
    local bestDistance = math.huge
    for index = 1, #settings.templateTokens do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local slotCenterX = left + 14 + column * 184 + 86
        local slotCenterY = top - 42 - row * 31 - 14
        local dx, dy = centerX - slotCenterX, centerY - slotCenterY
        local distance = dx * dx + dy * dy
        if distance < bestDistance then
            bestDistance = distance
            bestIndex = index - 1
        end
    end
    return bestIndex
end

local function FinishChipDrag(chip)
    chip:StopMovingOrSizing()
    local key = chip.tokenKey
    local oldIndex
    local tokens = settings.templateTokens
    for index, tokenKey in ipairs(tokens) do
        if tokenKey == key then oldIndex = index break end
    end
    if not oldIndex then LayoutSelectedChips() return end

    local targetIndex = FindNearestTokenSlot(chip)
    table.remove(tokens, oldIndex)
    table.insert(tokens, math.min(#tokens + 1, targetIndex + 1), key)
    ApplyTemplateChange(key)
end

LayoutSelectedChips = function()
    for _, definition in ipairs(TEMPLATE_TOKEN_DEFS) do
        local chip = templateChips[definition.key]
        if chip then chip:Hide() end
    end
    for index, key in ipairs(settings.templateTokens) do
        local chip = templateChips[key]
        if chip then
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", 14 + column * 184, -42 - row * 31)
            chip:SetText(string.format("%d  %s  {%s}", index,
                TEMPLATE_TOKEN_LABELS[key] or key, key))
            chip:Show()
        end
    end
end

RefreshTemplateEditor = function(animateKey)
    for key, checkbox in pairs(templateCheckboxes) do
        local selected = false
        for _, tokenKey in ipairs(settings.templateTokens) do
            if tokenKey == key then selected = true break end
        end
        checkbox:SetChecked(selected)
    end
    LayoutSelectedChips()
    RefreshTemplatePreview()
    local chip = animateKey and templateChips[animateKey]
    if chip and chip:IsShown() then
        UI.PlayMotion(chip, 0.35, 1, 0.94, 1, 0.16)
    end
end

for index, definition in ipairs(TEMPLATE_TOKEN_DEFS) do
    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local checkbox = UI.Checkbox(availableTokenCard,
        string.format("%s  {%s}", definition.label, definition.key), 174,
        function(checked)
            SetTokenSelected(definition.key, checked)
        end)
    checkbox:SetPoint("TOPLEFT", 14 + column * 184, -42 - row * 31)
    templateCheckboxes[definition.key] = checkbox

    local chip = UI.Button(templateOrderCard, "", 172, 28, "secondary")
    chip.tokenKey = definition.key
    chip:SetMovable(true)
    chip:RegisterForDrag("LeftButton")
    chip:SetClampedToScreen(true)
    chip:SetScript("OnDragStart", function(self)
        self:SetAlpha(0.82)
        self:StartMoving()
    end)
    chip:SetScript("OnDragStop", function(self)
        self:SetAlpha(1)
        FinishChipDrag(self)
    end)
    chip:Hide()
    templateChips[definition.key] = chip
end

clearTemplateButton:SetScript("OnClick", function()
    settings.templateTokens = {}
    ApplyTemplateChange()
end)

recommendTemplateButton:SetScript("OnClick", function()
    settings.templateLead = DEFAULT_TEMPLATE_LEAD
    settings.templateSuffix = ""
    settings.templateTokens = CopyTemplateTokens(DEFAULT_TEMPLATE_TOKENS)
    ApplyTemplateChange("puller")
end)

local function HideTemplateEditor()
    templateEditor:Hide()
    templateEditor:EnableKeyboard(false)
end

templateEditorClose:SetScript("OnClick", HideTemplateEditor)
doneTemplateButton:SetScript("OnClick", HideTemplateEditor)
templateEditor:SetScript("OnKeyDown", function(_, key)
    if key == "ESCAPE" then HideTemplateEditor() end
end)

OpenTemplateEditor = function()
    RefreshTemplateEditor()
    templateEditor:Show()
    templateEditor:Raise()
    templateEditor:EnableKeyboard(true)
    UI.PlayMotion(templateEditorCard, 0, 1, 0.96, 1, 0.18)
end

SyncTemplateBuilderUI = function()
    RefreshTemplatePreview()
    if templateEditor and templateEditor:IsShown() then
        RefreshTemplateEditor()
    end
end

local delayCheck = CreateSettingCheck(settingsLeftCard, "脱战后延迟通报", 16, -296, function(checked)
    settings.delayOutOfCombat = checked
    SaveSettings()
end, 260)
delayCheck:SetChecked(settings.delayOutOfCombat)

delayEdit = UI.EditBox(settingsLeftCard, "WhoAddDelayEdit", 48, 28, false)
delayEdit:SetPoint("TOPLEFT", 300, -294)
delayEdit:SetAutoFocus(false)
delayEdit:SetMaxLetters(2)
delayEdit:SetText(tostring(settings.delaySeconds))
local function CommitDelaySeconds()
    local value = math.max(1, math.min(30, tonumber(delayEdit:GetText()) or 3))
    settings.delaySeconds = value
    delayEdit:SetText(tostring(value))
    SaveSettings()
end
delayEdit:SetScript("OnEnterPressed", function(self)
    CommitDelaySeconds()
    self:ClearFocus()
end)
delayEdit:SetScript("OnEditFocusLost", function()
    CommitDelaySeconds()
end)
delayEdit:SetScript("OnEscapePressed", function(self)
    self:SetText(tostring(settings.delaySeconds))
    self:ClearFocus()
end)
local delaySuffix = UI.Label(settingsLeftCard, "秒", "GameFontNormalSmall", UI.colors.textDim)
delaySuffix:SetPoint("LEFT", delayEdit, "RIGHT", 6, 0)

local distanceCheck = CreateSettingCheck(settingsLeftCard, "通报中附加与怪物距离", 16, -330, function(checked)
    settings.includeDistance = checked
    if SyncTemplateBuilderUI then SyncTemplateBuilderUI() end
    SaveSettings()
end)
distanceCheck:SetChecked(settings.includeDistance)

do
    local rightTitle = UI.Label(settingsRightCard, "提醒方式", "GameFontNormalLarge", UI.colors.accent)
    rightTitle:SetPoint("TOPLEFT", 16, -14)
    local rightSubtitle = UI.Label(settingsRightCard, "文字、弹窗与声音可独立启用", "GameFontNormalSmall", UI.colors.textDim)
    rightSubtitle:SetPoint("TOPLEFT", 16, -35)
    local rightDivider = UI.Divider(settingsRightCard)
    rightDivider:SetPoint("TOPLEFT", 16, -56)
    rightDivider:SetPoint("TOPRIGHT", -16, -56)
end

CreateSettingLabel(settingsRightCard, "通报方式（可多选）", 16, -70)
local textCheck = CreateSettingCheck(settingsRightCard, "文字通报", 16, -94, function(checked)
    settings.textEnabled = checked
    if not checked then
        pendingAnnouncements.items = {}
        pendingAnnouncements.readyAt = 0
        pendingAnnouncements.waitingCombat = false
    end
    SaveSettings()
end)
textCheck:SetChecked(settings.textEnabled)

local popupCheck = CreateSettingCheck(settingsRightCard, "弹窗通报", 16, -126, function(checked)
    settings.popupEnabled = checked
    SaveSettings()
end)
popupCheck:SetChecked(settings.popupEnabled)

local soundCheck = CreateSettingCheck(settingsRightCard, "开怪声音提醒", 16, -158, function(checked)
    settings.soundEnabled = checked
    SaveSettings()
end)
soundCheck:SetChecked(settings.soundEnabled)

do
    local soundInfo = UI.Label(settingsRightCard,
        "默认音效：SOUNDKIT.IG_MAINMENU_OPEN", "GameFontNormalSmall", UI.colors.textDim, 376)
    soundInfo:SetPoint("TOPLEFT", 16, -190)
    soundInfo:SetJustifyH("LEFT")
    soundInfo:SetWordWrap(true)

    local testSoundBtn = UI.Button(settingsRightCard, "测试声音", 116, 30, "secondary")
    testSoundBtn:SetPoint("TOPLEFT", 16, -214)
    testSoundBtn:SetText("测试声音")
    testSoundBtn:SetScript("OnClick", function()
        PlayAlertSound(true)
    end)

    local testPopupBtn = UI.Button(settingsRightCard, "测试弹窗", 116, 30, "secondary")
    testPopupBtn:SetPoint("LEFT", testSoundBtn, "RIGHT", 8, 0)
    testPopupBtn:SetText("测试弹窗")
    testPopupBtn:SetScript("OnClick", function()
        local testRecord = selectedRecord or {
            puller = UnitName("player") or "测试玩家",
            mobDisplayName = "测试首领",
            mobName = "测试首领",
            action = "触发了",
            bossName = "WhoAdd 测试",
            sourceLabel = "本地测试",
            role = "boss",
            distance = 18.6,
            timeText = date("%H:%M:%S"),
        }
        ShowPullPopup(testRecord, true)
        PlayAlertSound(true)
    end)
end

do
    local actionDivider = UI.Divider(settingsRightCard)
    actionDivider:SetPoint("TOPLEFT", 16, -256)
    actionDivider:SetPoint("TOPRIGHT", -16, -256)

    local saveBtn = UI.Button(settingsRightCard, "立即保存", 116, 32, "primary")
    saveBtn:SetPoint("TOPLEFT", 16, -270)
    saveBtn:SetText("立即保存")
    saveBtn:SetScript("OnClick", function()
        SaveSettings()
        print(UI.hex.accent .. "[WhoAdd]|r 设置已写入 WhoAddDB")
    end)

    local resetBtn = UI.Button(settingsRightCard, "恢复默认", 106, 32, "secondary")
    resetBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    resetBtn:SetText("恢复默认")
    resetBtn:SetScript("OnClick", function()
        if UI.ShowConfirm then
            UI.ShowConfirm("恢复默认设置",
                "将通报范围、模板、延迟、声音、弹窗与距离设置恢复为默认值。",
                "恢复", function()
                    if ResetWhoAddSettings then ResetWhoAddSettings() end
                end, false)
        elseif StaticPopup_Show then
            StaticPopup_Show("WHOADD_RESET_SETTINGS")
        end
    end)
end

settingsStatus = UI.Label(settingsRightCard, "", "GameFontNormalSmall", UI.colors.success, 376)
settingsStatus:SetPoint("TOPLEFT", 16, -312)
settingsStatus:SetJustifyH("LEFT")
settingsStatus:SetText(UI.hex.success .. "所有设置修改后即时保存|r")

local settingsNote = UI.Label(settingsRightCard, "", "GameFontNormalSmall", UI.colors.textDim, 376)
settingsNote:SetPoint("TOPLEFT", 16, -338)
settingsNote:SetJustifyH("LEFT")
settingsNote:SetWordWrap(true)
settingsNote:SetText("说明：文字通报与弹窗通报可分别勾选；脱战延迟只影响文字通报，弹窗和声音会在确认开怪时立即触发。")

local creditsDivider = UI.Divider(settingsLeftCard)
creditsDivider:SetPoint("TOPLEFT", 16, -368)
creditsDivider:SetPoint("TOPRIGHT", -16, -368)

local creditsTitle = UI.Label(settingsLeftCard, "插件信息", "GameFontNormal", UI.colors.accent)
creditsTitle:SetPoint("TOPLEFT", 16, -386)

local creditsText = UI.Label(settingsLeftCard, "", "GameFontNormalSmall", UI.colors.textDim, 448)
creditsText:SetPoint("TOPLEFT", 16, -410)
creditsText:SetJustifyH("LEFT")
creditsText:SetWordWrap(true)
creditsText:SetText("原版插件 WhoAdd 首拉原版作者：甜甜哥不口胡-时光VI\n" ..
    "增强版作者：陳年老醋-时光VI <肯瑞托>公会")

SyncSettingsUI = function()
    if modeButton then
        modeButton:SetText("当前：" .. (reportModeLabels[settings.reportMode] or "仅通报团队 Boss") .. "（点击切换）")
        modeButton:SetSelected(true)
    end
    if SyncTemplateBuilderUI then SyncTemplateBuilderUI() end
    delayCheck:SetChecked(settings.delayOutOfCombat)
    delayEdit:SetText(tostring(settings.delaySeconds))
    distanceCheck:SetChecked(settings.includeDistance)
    textCheck:SetChecked(settings.textEnabled)
    popupCheck:SetChecked(settings.popupEnabled)
    soundCheck:SetChecked(settings.soundEnabled)
end
end

-- Boss 资料页
do
local bossesPage = pages[3]

local bossCard = UI.CreateCard(bossesPage, UI.colors.panel, UI.colors.border)
bossCard:SetAllPoints()

local bossTitle = UI.Label(bossCard, "Boss 资料库", "GameFontNormalLarge", UI.colors.accent)
bossTitle:SetPoint("TOPLEFT", 16, -14)

local bossSubtitle = UI.Label(bossCard, "首领本体、关联小怪、开怪 NPC 与动态遭遇规则",
    "GameFontNormalSmall", UI.colors.textDim)
bossSubtitle:SetPoint("TOPLEFT", 16, -35)

local bossBadge = UI.Label(bossCard, "WOTLK RAID DATA", "GameFontNormalSmall", UI.colors.accent)
bossBadge:SetPoint("TOPRIGHT", -16, -16)
bossBadge:SetJustifyH("RIGHT")

local bossScroll = UI.CreateScroll(bossCard, "WhoAddBossScroll")
bossScroll:SetPoint("TOPLEFT", 16, -56)
bossScroll:SetPoint("BOTTOMRIGHT", -18, -12)

local bossContent = CreateFrame("Frame", nil, bossScroll)
bossContent:SetSize(836, 400)
bossScroll:SetScrollChild(bossContent)

local bossText = UI.Label(bossContent, "", "ChatFontNormal", UI.colors.text, 836)
bossText:SetPoint("TOPLEFT", 4, -4)
bossText:SetJustifyH("LEFT")
bossText:SetWordWrap(true)

local function FormatIdList(ids, limit)
    if not ids or #ids == 0 then return "无" end
    local parts = {}
    local count = math.min(#ids, limit or 8)
    for i = 1, count do parts[#parts + 1] = tostring(ids[i]) end
    if #ids > count then parts[#parts + 1] = "…" end
    return table.concat(parts, ", ")
end

RefreshBossList = function()
    local grouped = {}
    local raidOrder = {}
    for _, raid in ipairs(RAID_ORDER) do
        grouped[raid] = {}
        raidOrder[#raidOrder + 1] = raid
    end
    for _, boss in ipairs(BOSS_LIST) do
        local raid = boss.raid or "其他"
        if not grouped[raid] then
            grouped[raid] = {}
            raidOrder[#raidOrder + 1] = raid
        end
        grouped[raid][#grouped[raid] + 1] = boss
    end

    local lines = {}
    lines[#lines + 1] = UI.hex.accent .. "WhoAdd Boss 资料库|r"
    lines[#lines + 1] = UI.hex.dim .. "支持首领本体、关联小怪、开怪 NPC 与动态遭遇战识别。|r"
    lines[#lines + 1] = ""

    for _, raid in ipairs(raidOrder) do
        local bosses = grouped[raid]
        if bosses and #bosses > 0 then
            lines[#lines + 1] = string.format("%s%s|r  %s(%d)|r", UI.hex.accent, raid, UI.hex.dim, #bosses)
            for _, boss in ipairs(bosses) do
                local special = ""
                if boss.dynamic then special = "  " .. UI.hex.dim .. "动态识别|r" end
                lines[#lines + 1] = string.format("  %s%s|r%s  %sNPC: %s|r",
                    UI.hex.text, boss.name, special, UI.hex.dim, FormatIdList(boss.ids, 8))
                if boss.adds and #boss.adds > 0 then
                    lines[#lines + 1] = string.format("    %s关联小怪|r: %s%s|r",
                        UI.hex.warning, UI.hex.dim, FormatIdList(boss.adds, 10))
                end
                if boss.openings and #boss.openings > 0 then
                    local labels = {}
                    for _, npcId in ipairs(boss.openings) do
                        local dialogue = DIALOGUE_NPCS[npcId]
                        local npcName = dialogue and dialogue.name or OPENING_NAME_OVERRIDES[npcId]
                        if npcName then
                            local suffix = dialogue and ("·" .. (dialogue.label or "开怪")) or ""
                            labels[#labels + 1] = string.format("%s(%d%s)", npcName, npcId,
                                suffix)
                        else
                            labels[#labels + 1] = tostring(npcId)
                        end
                    end
                    lines[#lines + 1] = "    " .. UI.hex.success .. "开怪NPC|r: " ..
                        UI.hex.dim .. table.concat(labels, ", ") .. "|r"
                end
            end
            lines[#lines + 1] = ""
        end
    end

    lines[#lines + 1] = UI.hex.success .. "特殊规则|r"
    lines[#lines + 1] = "  · 十字军的试炼 1-4：诺森德猛兽使用 34816/35909，加拉克苏斯使用 35035，阵营冠军使用 35766，瓦格里双子使用 35770；同时合并对话者与正常 BOSS/ADD 开怪者。"
    lines[#lines + 1] = "  · 锋鳞：团队目标指向远征军指挥官 33210 后，沿用对话开怪检测。"
    lines[#lines + 1] = "  · 尤格-萨隆：使用首个进入战斗的团队成员判定开怪，守护者和触须不作为开怪依据。"
    lines[#lines + 1] = "  · 基尔加丹：欺诈者之手 25588 记录为关联小怪，并参与“仅通报团队 Boss”范围。"
    lines[#lines + 1] = "  · 首领召唤出的 NPC 若未静态列出，会依据 SPELL_SUMMON 来源动态归入对应首领。"

    bossText:SetText(table.concat(lines, "\n"))
    local height = math.max(400, bossText:GetStringHeight() + 30)
    bossContent:SetHeight(height)
    if bossScroll.UpdateScrollRange then bossScroll.UpdateScrollRange() end
end
end

SelectTab = function(index)
    local previousTab = selectedTab
    selectedTab = math.max(1, math.min(#pages, index or 1))
    settings.selectedTab = selectedTab
    for i, page in ipairs(pages) do
        page:SetShown(i == selectedTab)
        tabUnderlines[i]:SetShown(i == selectedTab)
        tabButtons[i]:SetSelected(i == selectedTab)
        tabButtons[i]:SetAlpha(1)
    end
    if selectedTab == 1 then
        RefreshRecordList()
    elseif selectedTab == 3 then
        RefreshBossList()
    end
    if listFrame:IsShown() and selectedTab ~= previousTab then
        UI.PlayMotion(pages[selectedTab], 0, 1, 1, 1, 0.17)
    end
    if type(WhoAddDB) == "table" then
        WhoAddDB.selectedTab = selectedTab
    end
end
end

WhoAdd.loadStage = "构建主界面"
do
    local ok, err = pcall(BuildMainUI)
    if not ok then
        print("|cffff4444[WhoAdd]|r 主界面构建失败：" .. tostring(err))
        print("|cffff4444[WhoAdd]|r 开怪检测仍会继续加载，请把这条错误反馈给作者。")
    end
end
WhoAdd.loadStage = "注册事件"

UpdateWindowPosition = function()
    local window = type(WhoAddDB) == "table" and WhoAddDB.window
    listFrame:ClearAllPoints()
    if window and tonumber(window.x) and tonumber(window.y) then
        listFrame:SetPoint(window.point or "CENTER", UIParent,
            window.relativePoint or window.point or "CENTER",
            tonumber(window.x) or 0, tonumber(window.y) or 0)
    else
        listFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function EnsureMainFrameOnScreen()
    local wasShown = listFrame:IsShown()
    listFrame:SetAlpha(1)
    listFrame:Show()
    listFrame:Raise()
    if not wasShown then
        UI.PlayMotion(listFrame, 0, 1, 0.985, 1, 0.18)
    end
    local left, right = listFrame:GetLeft(), listFrame:GetRight()
    local top, bottom = listFrame:GetTop(), listFrame:GetBottom()
    local screenWidth = UIParent:GetWidth() or 1920
    local screenHeight = UIParent:GetHeight() or 1080
    local visible = left and right and top and bottom
        and right > 40 and left < screenWidth - 40
        and top > 40 and bottom < screenHeight - 40
    if not visible then
        listFrame:ClearAllPoints()
        listFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        if type(WhoAddDB) == "table" then
            WhoAddDB.window = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            }
            PersistToDisk()
        end
    end
end

local function ToggleMainFrame()
    if listFrame:IsShown() then
        listFrame:Hide()
    else
        EnsureMainFrameOnScreen()
        SelectTab(selectedTab or 1)
    end
end

local function OpenSettingsTab()
    EnsureMainFrameOnScreen()
    SelectTab(2)
end

local function OpenRecordsTab()
    EnsureMainFrameOnScreen()
    SelectTab(1)
end

-- 小地图按钮：使用 LibDBIcon-1.0
function WhoAdd.SetupMinimapIcon()
    local libStub = _G.LibStub
    local ldb = libStub and libStub("LibDataBroker-1.1", true)
    local ldbicon = libStub and libStub("LibDBIcon-1.0", true)
    if not ldb or not ldbicon then
        print("|cffff4444[WhoAdd]|r LibDBIcon 未加载，小地图图标不可用")
        return
    end

    if type(WhoAddDB) ~= "table" then WhoAddDB = {} end
    local minimapDB = type(WhoAddDB.minimap) == "table" and WhoAddDB.minimap or {}
    if minimapDB.minimapPos == nil then
        minimapDB.minimapPos = tonumber(WhoAddDB.minimapAngle) or 225
    end
    if minimapDB.hide == nil then minimapDB.hide = false end
    WhoAddDB.minimap = minimapDB
    WhoAddDB.minimapAngle = nil

    if ldbicon:IsRegistered("WhoAdd") then
        ldbicon:Refresh("WhoAdd", minimapDB)
        return
    end

    local function persistIconPosition()
        SaveSettings(true)
    end

    ldbicon.RegisterCallback(WhoAdd, "LibDBIcon_IconCreated", function(_, button, name)
        if name ~= "WhoAdd" or button.whoAddPositionHooked then return end
        button.whoAddPositionHooked = true
        button:HookScript("OnDragStop", persistIconPosition)
    end)

    local dataObject = ldb:NewDataObject("WhoAdd", {
        type = "launcher",
        text = "WhoAdd",
        icon = "Interface\\AddOns\\WhoAdd\\Media\\WhoAddIcon",
        OnClick = function(_, button)
            if button == "RightButton" then
                OpenSettingsTab()
            else
                ToggleMainFrame()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("WhoAdd " .. WhoAddVersion, 0.259, 0.647, 0.961)
            tooltip:AddLine("左键：打开/关闭引怪记录", 1, 1, 1)
            tooltip:AddLine("右键：打开设置", 1, 1, 1)
            tooltip:AddLine("拖动：移动小地图图标", 0.75, 0.75, 0.75)
        end,
    })
    ldbicon:Register("WhoAdd", dataObject, minimapDB)
end

function WhoAdd.RefreshMinimapIcon()
    local libStub = _G.LibStub
    local ldbicon = libStub and libStub("LibDBIcon-1.0", true)
    if ldbicon and ldbicon:IsRegistered("WhoAdd") and type(WhoAddDB.minimap) == "table" then
        ldbicon:Refresh("WhoAdd", WhoAddDB.minimap)
    end
end

-- ============================================================
-- 事件
-- ============================================================

WhoAdd:SetScript("OnUpdate", function(_, elapsed)
    local now = GetTime()
    if now >= nextHistoryPruneAt then
        nextHistoryPruneAt = now + 60
        PruneExpiredHistory()
    end
    if #pendingAnnouncements.items == 0 then return end
    if now < (WhoAdd.nextAnnouncementCheck or 0) then return end
    WhoAdd.nextAnnouncementCheck = now + 0.25

    if AnyoneInCombat() then
        pendingAnnouncements.waitingCombat = true
    elseif pendingAnnouncements.waitingCombat then
        pendingAnnouncements.waitingCombat = false
        pendingAnnouncements.readyAt = now + (tonumber(settings.delaySeconds) or 3)
    end
    FlushPendingAnnouncements()
end)

WhoAdd:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if addonName and loadedAddon and loadedAddon ~= addonName then return end
        InitDatabase()
        if not WhoAddBootAnnounced then
            WhoAddBootAnnounced = true
            print("|cff66ccff[WhoAdd]|r v" .. WhoAddVersion .. " 已加载，输入 /wadd 打开面板")
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if type(WhoAddDB) ~= "table" then InitDatabase() end
        BuildRosterCache()
        BuildPetMap()
        UpdateScanState()
        UpdateWindowPosition()
        local zoneName = GetRealZoneText and GetRealZoneText() or nil
        if lastZoneName ~= zoneName then
            lastZoneName = zoneName
            deadMobs = {}
            dynamicAddBoss = {}
        end
        if AnyoneInCombat() then
            suppressCurrentCombat = true
        else
            ResetCombatState("entering_world")
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        SaveHistory()
        SaveSettings(true)
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
        BuildRosterCache()
        BuildPetMap()
        UpdateScanState()
        ScheduleScan(0.05)
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        resetGeneration = resetGeneration + 1
        combatStartedAt = combatStartedAt or GetTime()
        BuildRosterCache()
        BuildPetMap()
        if not bossReported then
            local openingBoss
            local openingAt
            for _, entry in pairs(npcInteractions) do
                for npcGUID in pairs(entry.npcs or {}) do
                    local npcId = NpcIDFromGUID(npcGUID)
                    local dialogue = npcId and DIALOGUE_NPCS[npcId] or nil
                    local opening = npcId and OPENING_BY_ID[npcId] or nil
                    if dialogue and opening and opening.boss and not dialogue.raidWide then
                        local seenAt = entry.lastClickAt or entry.lastSeenAt or entry.firstAt or 0
                        if not openingAt or seenAt > openingAt then
                            openingBoss = opening.boss
                            openingAt = seenAt
                        end
                    end
                end
            end
            if openingBoss then
                if IsTocDialogueBoss(openingBoss) then
                    ScheduleDialogueFallback(openingBoss, 0.8)
                else
                    local record = ReportDialogueEncounter(openingBoss.name)
                    if record then ClearNpcInteractions() end
                end
            end
        end
        ScheduleScan(0.03)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if not AnyoneInCombat() then
            SaveHistory()
            PersistToDisk()
            ScheduleCombatReset()
            if #pendingAnnouncements.items > 0 then
                pendingAnnouncements.readyAt = GetTime() + (tonumber(settings.delaySeconds) or 3)
            end
        end
        return
    end

    if event == "ENCOUNTER_START" then
        local encounterId, encounterName, difficulty, groupSize = ...
        activeEncounter = {
            id = encounterId,
            name = encounterName,
            difficulty = difficulty,
            groupSize = groupSize,
            startedAt = GetTime(),
        }
        local registeredBoss = RegisterEncounterBoss(encounterName)
        local reportedBossKey = registeredBoss and ("boss:" .. tostring(registeredBoss.raid or "")
            .. ":" .. registeredBoss.name) or nil
        if encounterId and reportedBossKey and reportedMobs[reportedBossKey] then
            reportedEncounterBosses[encounterId] = true
        end
        if not encounterId or not reportedEncounterBosses[encounterId] then
            bossReported = false
            bossEngagedAt = nil
        end
        initialAddReports = 0
        if registeredBoss and registeredBoss.name == "尤格-萨隆"
            and (not reportedBossKey or not reportedMobs[reportedBossKey]) then
            local firstCombatPlayer = WhoAdd.firstCombatPlayer
            local firstCombatGUID = WhoAdd.firstCombatGUID
            local firstCombatUnit = WhoAdd.firstCombatUnit
            local firstCombatAt = WhoAdd.firstCombatAt
            if firstCombatPlayer and firstCombatAt and GetTime() - firstCombatAt <= 3 then
                local bossGUID, bossUnit = FindEncounterBossUnit()
                if not bossGUID and firstCombatUnit and UnitExists(firstCombatUnit) then
                    local targetUnit = UnitTargetToken(firstCombatUnit)
                    if UnitExists(targetUnit) then
                        local targetGUID = UnitGUID(targetUnit)
                        local _, targetRole = GetPullInfo(targetGUID, UnitName(targetUnit))
                        if targetRole == "add" then
                            bossGUID = targetGUID
                            bossUnit = targetUnit
                        end
                    end
                end
                if not bossGUID then
                    bossGUID = "Encounter-" .. tostring(encounterId or encounterName or "Yogg")
                        .. "-" .. tostring(math.floor(time()))
                end
                ReportPull({
                    guid = bossGUID,
                    mobName = encounterName or registeredBoss.name,
                    unit = bossUnit,
                    boss = registeredBoss,
                    role = "boss",
                    puller = firstCombatPlayer,
                    pullerGUID = firstCombatGUID,
                    source = "ENCOUNTER",
                    action = "首先进入战斗",
                    evidence = "MRT_STYLE_FIRST_COMBAT",
                    snapshot = CaptureSnapshot(bossGUID, encounterName or registeredBoss.name, bossUnit),
                })
                WhoAdd.firstCombatPlayer = nil
                WhoAdd.firstCombatGUID = nil
                WhoAdd.firstCombatUnit = nil
                WhoAdd.firstCombatAt = nil
            end
        end
        local clickers = GetNpcInteractionSummary(encounterName)
        if #clickers > 0 then
            local dialogueBoss = BOSS_BY_NAME[encounterName] or registeredBoss
            if IsTocDialogueBoss(dialogueBoss) then
                ScheduleDialogueFallback(dialogueBoss, 0.8)
            else
                ReportDialogueEncounter(encounterName)
                ClearNpcInteractions()
            end
        end
        ScheduleScan(0.03)
        return
    end

    if event == "ENCOUNTER_END" then
        local encounterId, encounterName = ...
        if activeEncounter and activeEncounter.id == encounterId then
            activeEncounter.endedAt = GetTime()
            activeEncounter.endedName = encounterName
        end
        return
    end

    if event == "UNIT_TARGET" then
        local unit = ...
        HandleUnitTarget(unit)
        return
    end

    if event == "UNIT_FLAGS" then
        local unit = ...
        if not combatStartedAt and not WhoAdd.firstCombatPlayer
            and unit and UnitAffectingCombat(unit) then
            local isGroupUnit = unit == "player"
                or (unit:match("^raid%d+$") ~= nil)
                or (unit:match("^party%d+$") ~= nil)
                or (unit:match("^raidpet%d+$") ~= nil)
                or (unit:match("^partypet%d+$") ~= nil)
            if isGroupUnit then
                local ownerUnit = unit
                local ownerName
                local ownerGUID
                if unit:find("pet", 1, true) then
                    ownerUnit = unit:gsub("pet", "")
                    if UnitExists(ownerUnit) then
                        ownerName = UnitName(ownerUnit)
                        ownerGUID = UnitGUID(ownerUnit)
                    end
                else
                    ownerName, ownerGUID = ResolveOwner(unit)
                end
                if ownerName then
                    WhoAdd.firstCombatPlayer = ownerName
                    WhoAdd.firstCombatGUID = ownerGUID
                    WhoAdd.firstCombatUnit = ownerUnit
                    WhoAdd.firstCombatAt = GetTime()
                    DebugPrint("MRT式首战记录: " .. tostring(ownerName))
                end
            end
        end
        return
    end

    if event == "GOSSIP_SHOW" then
        TrackNpcInteraction("player", true)
        return
    end

    if event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT"
        or event == "NAME_PLATE_UNIT_ADDED" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        CheckSpecialTargetForUnit("player")
        EvaluateNpcTarget("target", "TARGET")
        ScheduleScan(0.03)
        return
    end

    if event == "ZONE_CHANGED_NEW_AREA" then
        lastZoneName = GetRealZoneText and GetRealZoneText() or nil
        deadMobs = {}
        dynamicAddBoss = {}
        ResetCombatState("zone_changed")
        UpdateScanState()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog()
        return
    end
end)

-- ============================================================
-- 斜杠命令
-- ============================================================

SLASH_WHOADD1 = "/wadd"
SLASH_WHOADD2 = "/whoadd"
local function SafeOpen(label, callback)
    local ok, err = pcall(callback)
    if not ok then
        print("|cffff4444[WhoAdd]|r " .. label .. "失败：" .. tostring(err))
    end
end

SlashCmdList["WHOADD"] = function(message)
    local command, rest = tostring(message or ""):match("^(%S*)%s*(.*)$")
    command = string.lower(command or "")

    if command == "" then
        SafeOpen("打开主面板", OpenRecordsTab)
    elseif command == "close" then
        listFrame:Hide()
    elseif command == "reset" then
        if ClearRecords then ClearRecords() end
        print("|cff66ccff[WhoAdd]|r 已清空本次记录")
    elseif command == "settings" or command == "config" then
        SafeOpen("打开设置页", OpenSettingsTab)
    elseif command == "all" then
        SetReportMode("all")
        print("|cff66ccff[WhoAdd]|r 通报范围：通报所有")
    elseif command == "boss" then
        SetReportMode("boss")
        print("|cff66ccff[WhoAdd]|r 通报范围：仅通报团队 Boss")
    elseif command == "none" then
        SetReportMode("none")
        print("|cff66ccff[WhoAdd]|r 通报范围：不通报")
    elseif command == "bosses" or command == "data" then
        SafeOpen("打开Boss资料页", function()
            EnsureMainFrameOnScreen()
            SelectTab(3)
        end)
    elseif command == "save" then
        SaveSettings()
        print("|cff66ccff[WhoAdd]|r 设置已即时保存")
    elseif command == "test" then
        local testRecord = selectedRecord or {
            puller = UnitName("player") or "测试玩家",
            mobDisplayName = "测试首领",
            mobName = "测试首领",
            action = "触发了",
            bossName = "WhoAdd 测试",
            sourceLabel = "本地测试",
            role = "boss",
            distance = 18.6,
            timeText = date("%H:%M:%S"),
        }
        local ok, err = pcall(function()
            local shown = ShowPullPopup(testRecord, true)
            if not shown then error("弹窗对象未创建或被隐藏") end
            PlayAlertSound(true)
        end)
        if ok then
            print("|cff66ccff[WhoAdd]|r 测试已触发：应出现开怪弹窗并播放声音")
        else
            print("|cffff4444[WhoAdd]|r 测试失败：" .. tostring(err))
        end
    elseif command == "debug" then
        debugEnabled = not debugEnabled
        SaveSettings(true)
        print("|cff66ccff[WhoAdd]|r 调试输出：" .. (debugEnabled and "开启" or "关闭"))
    else
        print("|cff66ccff[WhoAdd]|r 指令：")
        print("  /wadd            打开主面板")
        print("  /wadd close      关闭主面板")
        print("  /wadd reset      清空记录")
        print("  /wadd settings   打开设置页")
        print("  /wadd bosses     查看 Boss 资料库")
        print("  /wadd all        通报所有")
        print("  /wadd boss       仅通报团队 Boss")
        print("  /wadd none       不通报")
        print("  /wadd save       立即保存设置")
        print("  /wadd test       测试弹窗与声音")
        print("  /wadd debug      切换调试输出")
    end
end
