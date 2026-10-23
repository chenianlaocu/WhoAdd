-- 时间窗口关联开怪
-- 用于“关联小怪与首领在指定时间内一同进入战斗才算开怪”的遭遇。

local _, WA = ...
local WhoAdd = WA and WA.WhoAdd
local api = WA and WA.Runtime

if not WhoAdd or not api then
    print("|cffff4444[WhoAdd]|r 关联开怪模块未加载：核心接口不可用")
    return
end

local LP = WhoAdd.LinkedPulls or {}
local rulesByNpc = {}
local rulesByBoss = {}
local pendingByBoss = {}

for npcId, rule in pairs(WA.Catalog.linkedWindowPulls or {}) do
    npcId = tonumber(npcId)
    if npcId and type(rule) == "table" and type(rule.boss) == "string" then
        local normalized = {
            boss = rule.boss,
            window = math.max(0.1, tonumber(rule.window) or 5),
            label = rule.label,
        }
        rulesByNpc[npcId] = normalized
        rulesByBoss[normalized.boss] = normalized
    end
end

local function CopyInfo(info)
    local copy = {}
    for key, value in pairs(info) do copy[key] = value end
    return copy
end

-- false 表示该单位只作为候选，当前不应生成记录；table 表示首领记录已合并且可继续处理。
function LP.PreprocessPull(info, npcId)
    if type(info) ~= "table" then return nil end
    local now = GetTime()
    local addRule = rulesByNpc[tonumber(npcId) or 0]

    if addRule then
        local pending = pendingByBoss[addRule.boss]
        if not pending or now - pending.at > addRule.window then
            pendingByBoss[addRule.boss] = {
                at = now,
                puller = info.puller,
                pullerGUID = info.pullerGUID,
                mobName = info.mobName or addRule.label or "关联小怪",
            }
            api.DebugPrint(string.format("记录%s候选，等待%s在%.0f秒内进入战斗",
                tostring(info.mobName or addRule.label), addRule.boss, addRule.window))
        end
        return false
    end

    local bossName = info.boss and info.boss.name
    local bossRule = bossName and rulesByBoss[bossName]
    if info.role == "boss" and bossRule then
        local pending = pendingByBoss[bossName]
        if pending and now - pending.at <= bossRule.window then
            pendingByBoss[bossName] = nil
            local merged = CopyInfo(info)
            merged.puller = pending.puller or merged.puller
            merged.pullerGUID = pending.pullerGUID or merged.pullerGUID
            merged.action = string.format("与%s一同进入战斗，触发%s开怪",
                pending.mobName, bossName)
            merged.evidence = "LINKED_WINDOW"
            merged.linkedAddName = pending.mobName
            api.DebugPrint(string.format("合并%s与%s开怪", tostring(pending.mobName), bossName))
            return merged
        end
        pendingByBoss[bossName] = nil
    end
    return nil
end

function LP.Reset()
    pendingByBoss = {}
end

WhoAdd.LinkedPulls = LP
WA.LinkedPulls = LP
