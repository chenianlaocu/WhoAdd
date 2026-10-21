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

local ULDUAR_AREA_ID = 603
local SARA_NPC_ID = 33134
local YOGG_BOSS_IDS = { [33288] = true, [33890] = true }
local YOGG_TERMS = { "尤格", "yogg", "疯狂阶梯", "descent into madness" }
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

local function HasYoggBossUnit()
    for index = 1, 5 do
        local unit = "boss" .. index
        if UnitExists(unit) and YOGG_BOSS_IDS[api.NpcIDFromGUID(UnitGUID(unit)) or 0] then
            return true
        end
    end
    return false
end

local function HasSaraTarget()
    local units = { "target", "focus", "mouseover" }
    for _, unit in ipairs(api.GetGroupUnits()) do
        units[#units + 1] = api.UnitTargetToken(unit)
    end
    for _, unit in ipairs(units) do
        if unit and UnitExists(unit) and api.NpcIDFromGUID(UnitGUID(unit)) == SARA_NPC_ID then
            return true
        end
    end
    return false
end

function YP.IsScene()
    if HasYoggBossUnit() then return true end

    local zone = GetRealZoneText and GetRealZoneText() or ""
    local subzone = GetSubZoneText and GetSubZoneText() or ""
    local minimap = GetMinimapZoneText and GetMinimapZoneText() or ""
    local location = zone .. " " .. subzone .. " " .. minimap
    if ContainsAny(location, YOGG_TERMS) then return true end
    if not IsUlduar() then return false end
    return ContainsAny(location, PRISON_TERMS) or HasSaraTarget()
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

local function StopWatcher()
    if YP.frame then YP.frame:Hide() end
    YP.watchStartedAt = nil
end

function YP.Report(puller, pullerGUID, pullerUnit)
    if YP.reported or not puller or not YP.IsScene() then return nil end
    local boss = api.GetBossByName("尤格-萨隆")
    if not boss then return nil end

    api.BuildRosterCache()
    api.BuildPetMap()

    local syntheticGUID = "YoggPrison-" .. tostring(math.floor(GetTime() * 1000))
    local snapshotGUID = syntheticGUID
    local snapshotName = boss.name
    local snapshotUnit
    local targetUnit = api.UnitTargetToken(pullerUnit)
    if targetUnit and UnitExists(targetUnit)
        and not UnitIsPlayer(targetUnit)
        and (not UnitCanAttack or UnitCanAttack("player", targetUnit)) then
        snapshotGUID = UnitGUID(targetUnit) or snapshotGUID
        snapshotName = UnitName(targetUnit) or snapshotName
        snapshotUnit = targetUnit
    end

    YP.reported = true
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

    WhoAdd.firstCombatPlayer = nil
    WhoAdd.firstCombatGUID = nil
    WhoAdd.firstCombatUnit = nil
    WhoAdd.firstCombatAt = nil
    api.DebugPrint("尤格监狱首战记录: " .. tostring(puller))
    StopWatcher()
    return record
end

function YP.ObserveUnit(unit)
    if YP.reported or not unit then return end
    local name, guid, ownerUnit = ResolveGroupOwner(unit)
    if name and UnitAffectingCombat(unit) and YP.IsScene() then
        YP.Report(name, guid, ownerUnit)
    end
end

function YP.Scan()
    if YP.reported then return end
    if not YP.IsScene() then
        StopWatcher()
        return
    end
    local name, guid, unit = FindFirstCombatPlayer()
    if name then YP.Report(name, guid, unit) end
end

function YP.StartWatcher()
    if YP.reported or not YP.IsScene() then return end
    if YP.frame then
        YP.watchStartedAt = YP.watchStartedAt or GetTime()
        YP.frame:Show()
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
end

function YP.Reset()
    YP.reported = false
    StopWatcher()
    YP.StartWatcher()
end

WhoAdd.YoggPrison = YP
WA.YoggPrison = YP
