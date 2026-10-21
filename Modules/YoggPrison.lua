-- 尤格-萨隆监狱场景特调
-- 在 BOSS 本体出现前，以第一个进入战斗的团队成员作为开怪者。

local _, WA = ...
local WhoAdd = WA and WA.WhoAdd
local api = WA and WA.Runtime

if not WhoAdd or not api then
    print("|cffff4444[WhoAdd]|r 尤格监狱模块未加载：核心接口不可用")
    return
end

local YP = WhoAdd.YoggPrison or {}
YP.reported = false
YP.ticker = nil
YP.watchStartedAt = nil
YP.sceneSeen = false
YP.firstCombatant = nil

local ULDUAR_AREA_ID = 603
local YOGG_IDS = {
    [33134] = true, -- 萨拉
    [33136] = true, -- 尤格萨隆的守护者
    [33288] = true, -- 尤格-萨隆
    [33890] = true, -- 尤格-萨隆（遭遇单位）
    [33966] = true, -- 碾压触须
    [33983] = true, -- 腐蚀触须
    [33985] = true, -- 缠绕触须
    [33988] = true, -- 不朽守护者
}
local YOGG_TERMS = {
    "尤格-萨隆的监狱", "尤格萨隆的监狱",
    "yogg-saron's prison", "yogg-saron prison", "yogg prison",
    "尤格", "yogg", "疯狂阶梯", "descent into madness",
}
local PRISON_TERMS = { "监狱", "prison" }
local ULDUAR_TERMS = {
    "奥杜尔", "奧杜爾", "奥杜亚", "奧杜亞", "ulduar",
}

local function ContainsAny(text, terms)
    if type(text) ~= "string" or text == "" then return false end
    local lower = string.lower(text)
    for _, term in ipairs(terms) do
        if lower:find(term, 1, true) then return true end
    end
    return false
end

local function IsUlduar()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    if ContainsAny(zone, ULDUAR_TERMS) then return true end
    if GetCurrentMapAreaID then
        local ok, areaId = pcall(GetCurrentMapAreaID)
        if ok and tonumber(areaId) == ULDUAR_AREA_ID then return true end
    end
    return false
end

local function IsUlduarContext()
    return IsUlduar() or YP.IsScene()
end

local function HasYoggUnit()
    local units = {}
    for index = 1, 5 do units[#units + 1] = "boss" .. index end
    for index = 1, 40 do units[#units + 1] = "nameplate" .. index end
    units[#units + 1] = "target"
    units[#units + 1] = "focus"
    units[#units + 1] = "mouseover"
    for _, unit in ipairs(api.GetGroupUnits()) do
        units[#units + 1] = api.UnitTargetToken(unit)
    end
    for _, unit in ipairs(units) do
        if unit and UnitExists(unit) and YOGG_IDS[api.NpcIDFromGUID(UnitGUID(unit)) or 0] then
            return true
        end
    end
    return false
end

function YP.IsScene()
    if YP.sceneSeen then return true end

    local zone = GetRealZoneText and GetRealZoneText() or ""
    local generalZone = GetZoneText and GetZoneText() or ""
    local subzone = GetSubZoneText and GetSubZoneText() or ""
    local minimap = GetMinimapZoneText and GetMinimapZoneText() or ""
    local location = zone .. " " .. generalZone .. " " .. subzone .. " " .. minimap
    if ContainsAny(location, YOGG_TERMS) then
        YP.sceneSeen = true
        api.DebugPrint("尤格监狱场景已识别: " .. location)
        return true
    end
    if not IsUlduar() then return false end
    if HasYoggUnit() or ContainsAny(location, PRISON_TERMS) then
        YP.sceneSeen = true
        api.DebugPrint("尤格监狱单位已识别: " .. location)
        return true
    end
    return false
end

local function ResolveGroupOwner(unit)
    if not unit or not UnitExists(unit) then return nil end
    local ownerUnit = unit
    if not UnitIsPlayer(unit) then
        local inGroupPet = (UnitPlayerOrPetInRaid and UnitPlayerOrPetInRaid(unit))
            or (UnitPlayerOrPetInParty and UnitPlayerOrPetInParty(unit))
        if not inGroupPet then return nil end
        ownerUnit = unit == "pet" and "player" or unit:gsub("pet", "")
    end
    local name, guid = api.ResolveOwner(ownerUnit)
    if not name then return nil end
    return name, guid, ownerUnit
end

local function FindFirstCombatPlayer()
    api.BuildRosterCache()
    for _, unit in ipairs(api.GetGroupUnits()) do
        if UnitExists(unit) and UnitAffectingCombat(unit) then
            local name, guid = api.ResolveOwner(unit)
            if name then return name, guid, unit end
        end
    end
    return nil
end

local function ClearFirstCombatant()
    YP.firstCombatant = nil
    WhoAdd.firstCombatPlayer = nil
    WhoAdd.firstCombatGUID = nil
    WhoAdd.firstCombatUnit = nil
    WhoAdd.firstCombatAt = nil
end

-- MRT WhoPulled 只关心团队实例内首个进入战斗的成员。这里先缓存下来，
-- 等“尤格-萨隆的监狱”子区域文本刷新后再立即生成通报。
local function RememberFirstCombatant(name, guid, unit, mobGUID, mobName)
    if YP.reported or not name or YP.firstCombatant then return end
    YP.firstCombatant = {
        name = name,
        guid = guid,
        unit = unit,
        mobGUID = mobGUID,
        mobName = mobName,
        at = GetTime(),
    }
    WhoAdd.firstCombatPlayer = name
    WhoAdd.firstCombatGUID = guid
    WhoAdd.firstCombatUnit = unit
    WhoAdd.firstCombatAt = YP.firstCombatant.at
    api.DebugPrint("尤格监狱候选首战: " .. tostring(name))
end

local function StopWatcher()
    if YP.frame then YP.frame:Hide() end
    YP.watchStartedAt = nil
end

function YP.Report(puller, pullerGUID, pullerUnit, mobGUID, mobName)
    if YP.reported or not puller or not YP.IsScene() then return nil end
    local boss = api.GetBossByName("尤格-萨隆")
    if not boss then return nil end

    api.BuildRosterCache()
    api.BuildPetMap()

    local syntheticGUID = "YoggPrison-" .. tostring(math.floor(GetTime() * 1000))
    local snapshotGUID = mobGUID or syntheticGUID
    local snapshotName = mobName or boss.name
    local snapshotUnit = mobGUID and api.FindUnitForGUID(mobGUID) or nil
    local targetUnit = api.UnitTargetToken(pullerUnit)
    if not mobGUID and targetUnit and UnitExists(targetUnit)
        and not UnitIsPlayer(targetUnit)
        and (not UnitCanAttack or UnitCanAttack("player", targetUnit)) then
        snapshotGUID = UnitGUID(targetUnit) or snapshotGUID
        snapshotName = UnitName(targetUnit) or snapshotName
        snapshotUnit = targetUnit
    end

    YP.reported = true
    api.AllowCurrentCombatReport()
    api.EnsureCombatStarted()
    local record = api.ReportPull({
        guid = syntheticGUID,
        mobName = boss.name,
        boss = boss,
        role = "boss",
        puller = puller,
        pullerGUID = pullerGUID,
        source = "YOGG_PRISON",
        action = "在监狱场景首先进入战斗",
        evidence = "YOGG_PRISON_FIRST_COMBAT",
        snapshot = api.CaptureSnapshot(snapshotGUID, snapshotName, snapshotUnit),
    })
    if not record then
        YP.reported = false
        return nil
    end

    ClearFirstCombatant()
    api.DebugPrint("尤格监狱首战记录: " .. tostring(puller))
    StopWatcher()
    return record
end

function YP.ObserveUnit(unit)
    if YP.reported or not unit then return end
    local name, guid, ownerUnit = ResolveGroupOwner(unit)
    if not name or not UnitAffectingCombat(unit) then return end

    if IsUlduarContext() then RememberFirstCombatant(name, guid, ownerUnit) end
    if YP.IsScene() then YP.Report(name, guid, ownerUnit) end
end

function YP.ObserveCombatLog(sourceName, sourceGUID, sourceIsGroup, mobGUID, mobName)
    if YP.reported or not sourceIsGroup or not sourceName or not IsUlduarContext() then return end
    local ownerName, ownerGUID = api.ResolveOwnerByGUID(sourceGUID, sourceName)
    if not ownerName then return end

    RememberFirstCombatant(ownerName, ownerGUID, nil, mobGUID, mobName)
    if YP.IsScene() then YP.Report(ownerName, ownerGUID, nil, mobGUID, mobName) end
end

function YP.Scan()
    if YP.reported then return end
    local inUlduar = IsUlduarContext()
    local scene = YP.IsScene()
    if not inUlduar and not scene then return end

    if not YP.firstCombatant then
        local name, guid, unit = FindFirstCombatPlayer()
        if name then RememberFirstCombatant(name, guid, unit) end
    end
    if not scene or not YP.firstCombatant then return end

    local first = YP.firstCombatant
    YP.Report(first.name, first.guid, first.unit, first.mobGUID, first.mobName)
end

function YP.StartWatcher()
    if YP.reported then return end
    local ulduar = IsUlduar()
    if not ulduar and not YP.IsScene() then return end
    if YP.frame then
        YP.watchStartedAt = YP.watchStartedAt or GetTime()
        YP.frame:Show()
        YP.Scan()
        return
    end

    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed < 0.1 then return end
        elapsed = 0
        YP.Scan()
    end)
    YP.frame = frame
    YP.watchStartedAt = GetTime()
    frame:Show()
    YP.Scan()
end

function YP.Reset()
    YP.reported = false
    YP.sceneSeen = false
    ClearFirstCombatant()
    StopWatcher()
    YP.StartWatcher()
end

function YP.InvalidateScene()
    YP.sceneSeen = false
end

WhoAdd.YoggPrison = YP
WA.YoggPrison = YP
