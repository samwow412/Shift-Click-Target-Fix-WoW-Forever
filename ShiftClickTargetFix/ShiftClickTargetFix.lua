--[[
  ShiftClickTargetFix

  12.0.7+ blocks modified SecureUnitButton clicks that resolve to "target".
  Route Shift/Ctrl/Alt + Left through the ungated "click" action to a SecureActionButton proxy.

  Enabled modifiers override other click-cast addons (Clique, Ellesmere, etc.).
  Disabled modifiers are left alone, so Shift+click heals can coexist with
  Ctrl+click targeting (or any other split). It wraps ClickCastFrames so ElvUI /
  Ellesmere / Clique / Gladius frames get the fix on the enabled keys only.

  Never touch nameplates. Platynator/Plater reparent the default UnitFrame; a
  SecureActionButton child makes SetParent protected and default plates stack.

  Do not walk compact-frame children or hook SetUpFrame synchronously.
]]

local ADDON = "ShiftClickTargetFix"

local targetProxies = setmetatable({}, { __mode = "k" })
local attachedFrames = setmetatable({}, { __mode = "k" })
local pendingApply = false
local lastAppliedCount = 0
local clickCastWrapper
local clickCastOld

local db
local defaults = { shift = true, ctrl = true, alt = true, combos = true }

-- Secure buttons build the modifier prefix in the fixed order alt-ctrl-shift-,
-- so "alt-shift", "alt-ctrl-shift" etc. are separate attribute names.
local MODIFIERS = { "shift", "ctrl", "alt", "alt-shift", "alt-ctrl", "ctrl-shift", "alt-ctrl-shift" }

-- A single modifier follows its own toggle. A combo is on when "combos" is on
-- and every key in it is enabled.
local function ModEnabled(mod)
    if not db then
        return false
    end
    local parts = 0
    for key in mod:gmatch("[^-]+") do
        parts = parts + 1
        if not db[key] then
            return false
        end
    end
    if parts > 1 and not db.combos then
        return false
    end
    return true
end

local UNIT_FRAME_NAME_PATTERNS = {
    "^PlayerFrame$",
    "^TargetFrame$",
    "^FocusFrame$",
    "^TargetFrameToT$",
    "^FocusFrameToT$",
    "^PetFrame$",
    "^Boss%d+TargetFrame$",
    "^CompactPartyFrameMember%d+$",
    "^CompactRaidFrame%d+$",
    "^CompactRaidGroup%d+Member%d+$",
    "^CompactArenaFrameMember%d+$",
    "^ArenaEnemyFrame%d+$",
    "^ArenaPrepFrame%d+$",
    "^PartyFrameMemberFrame%d+$",
    "^PartyMemberFrame%d+$", -- Classic-style party frames
    -- Party pet frames (raid-style, Classic-style and retail party frame)
    "^CompactPartyFramePet%d+$",
    "^CompactRaidFramePet%d+$",
    "^PartyMemberFrame%dPetFrame$",
    "^PartyFrameMemberFrame%dPetFrame$",
    "^PartyMemberFramePetFrame%d+$",
}

local function LoadDB()
    if type(ShiftClickTargetFixDB) ~= "table" then
        ShiftClickTargetFixDB = {}
    end
    db = ShiftClickTargetFixDB
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = v
        end
    end
end

LoadDB()

local function SafeTrim(s)
    if strtrim then
        return strtrim(s or "")
    end
    return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function FrameName(frame)
    if frame and frame.GetName then
        return frame:GetName() or ""
    end
    return ""
end

local function MatchesUnitFrameName(name)
    if name == "" then
        return false
    end
    for _, pattern in ipairs(UNIT_FRAME_NAME_PATTERNS) do
        if name:match(pattern) then
            return true
        end
    end
    return false
end

local function IsAuraOrChromeFrame(frame)
    local name = FrameName(frame):lower()
    if name == "" then
        return false
    end
    if name:find("buff", 1, true)
        or name:find("debuff", 1, true)
        or name:find("aura", 1, true)
        or name:find("dispel", 1, true)
        or name:find("private", 1, true)
        or name:find("cooldown", 1, true)
        or name:find("status", 1, true)
        or name:find("healthbar", 1, true)
        or name:find("manabar", 1, true)
        or name:find("powerbar", 1, true) then
        return true
    end
    return false
end

local NAMEPLATE_NAME_MARKERS = {
    "nameplate",
    "platynator",
    "plater",
    "kuinameplates",
    "tidyplates",
    "neatplates",
    "threatplates",
    "betterblizzplates",
}

local function GetUnitToken(frame)
    if not frame then
        return nil
    end
    local unit = frame.unit
    if type(unit) ~= "string" and frame.GetAttribute then
        local ok, attr = pcall(frame.GetAttribute, frame, "unit")
        if ok then
            unit = attr
        end
    end
    if type(unit) ~= "string" then
        unit = frame.displayedUnit
    end
    if type(unit) == "string" then
        return unit
    end
    return nil
end

local function IsNameplateUnitToken(unit)
    return type(unit) == "string" and unit:find("^nameplate", 1) ~= nil
end

local function NameLooksLikeNameplate(name)
    if not name or name == "" then
        return false
    end
    local lower = name:lower()
    for _, marker in ipairs(NAMEPLATE_NAME_MARKERS) do
        if lower:find(marker, 1, true) then
            return true
        end
    end
    return false
end

-- 12.1 nameplate UnitFrames are pooled CompactUnitFrames: often unnamed, no
-- isNamePlate flag, and Platynator reparents them onto an unnamed hidden frame.
local function IsNameplateRelatedFrame(frame)
    if not frame then
        return false
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return true
    end

    if frame.isNamePlate
        or frame.IsUnitNameplate
        or frame.GetNamePlateFrame
        or frame.namePlateFrame
        or frame.PlateFrame
        or frame.Plater
        or (frame.HealthBarsContainer and frame.CastBarsContainer)
    then
        return true
    end

    if IsNameplateUnitToken(GetUnitToken(frame)) then
        return true
    end

    if NameLooksLikeNameplate(FrameName(frame)) then
        return true
    end

    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local unit = GetUnitToken(frame)
        if unit then
            local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
            if ok and plate and (plate == frame or plate.UnitFrame == frame) then
                return true
            end
        end
    end

    local current = frame
    for _ = 1, 12 do
        if not current then
            break
        end
        if current.isNamePlate or current.GetNamePlateFrame or current.namePlateFrame or current.PlateFrame then
            return true
        end
        if NameLooksLikeNameplate(FrameName(current)) then
            return true
        end
        if current.GetParent then
            local ok, parent = pcall(current.GetParent, current)
            current = (ok and parent) or nil
        else
            current = nil
        end
    end

    return false
end

-- Named Blizzard unit buttons, plus any non-nameplate ClickCastFrames entry
-- (ElvUI, Ellesmere, Clique, Gladius, etc.).
local function IsAllowedUnitButton(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then
        return false
    end
    if IsNameplateRelatedFrame(frame) then
        return false
    end
    if not frame.SetAttribute or not frame.GetAttribute then
        return false
    end
    if not frame.IsObjectType or not frame:IsObjectType("Button") then
        return false
    end
    if IsAuraOrChromeFrame(frame) then
        return false
    end

    if MatchesUnitFrameName(FrameName(frame)) then
        return true
    end

    if type(ClickCastFrames) == "table" and ClickCastFrames[frame] then
        return true
    end

    return false
end

local function GetTargetProxy(frame)
    local proxy = targetProxies[frame]
    if not proxy then
        proxy = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
        proxy:SetSize(1, 1)
        proxy:SetAlpha(0)
        proxy:EnableMouse(false)
        proxy:RegisterForClicks("AnyUp")
        proxy:SetAttribute("type", "target")
        for i = 1, 5 do
            proxy:SetAttribute("type" .. i, "target")
        end
        proxy:SetAttribute("useparent-unit", true)
        proxy:SetAttribute("useOnKeyDown", false)
        targetProxies[frame] = proxy
    end
    return proxy
end

local function SafeGetAttribute(frame, key)
    if not frame or not frame.GetAttribute then
        return nil
    end
    local ok, value = pcall(frame.GetAttribute, frame, key)
    if ok then
        return value
    end
    return nil
end

local function ModifierStillAttached(frame, mod)
    local shiftType = SafeGetAttribute(frame, "*" .. mod .. "-type1")
        or SafeGetAttribute(frame, mod .. "-type1")
    if shiftType ~= "click" then
        return false
    end
    local proxy = targetProxies[frame]
    local clickBtn = SafeGetAttribute(frame, "*" .. mod .. "-clickbutton1")
        or SafeGetAttribute(frame, mod .. "-clickbutton1")
    return proxy and clickBtn == proxy
end

-- Always override other addons on enabled modifiers. That is the point of this addon.
local function ShouldAttachForModifier(frame, mod)
    if not ModEnabled(mod) then
        return false
    end
    if ModifierStillAttached(frame, mod) then
        return false
    end
    return true
end

local function ClearModifierAttributes(frame, mod)
    pcall(function()
        frame:SetAttribute(mod .. "-type1", nil)
        frame:SetAttribute("*" .. mod .. "-type1", nil)
        frame:SetAttribute(mod .. "-clickbutton1", nil)
        frame:SetAttribute("*" .. mod .. "-clickbutton1", nil)
    end)
end

-- Only strip attributes we installed. Never wipe Clique/Ellesmere heals on a
-- modifier the user turned off in our settings.
local function ReleaseModifierIfOurs(frame, mod)
    if ModifierStillAttached(frame, mod) then
        ClearModifierAttributes(frame, mod)
    end
end

local function AttachTargetFix(frame)
    if not IsAllowedUnitButton(frame) then
        return false
    end

    local willAttach = false
    for _, mod in ipairs(MODIFIERS) do
        if ShouldAttachForModifier(frame, mod) then
            willAttach = true
            break
        end
    end

    if not willAttach then
        for _, mod in ipairs(MODIFIERS) do
            if not ModEnabled(mod) then
                ReleaseModifierIfOurs(frame, mod)
            end
        end
        return false
    end

    local proxy = GetTargetProxy(frame)
    local attachedAny = false

    for _, mod in ipairs(MODIFIERS) do
        if ShouldAttachForModifier(frame, mod) then
            local ok = pcall(function()
                frame:SetAttribute(mod .. "-type1", nil)
                frame:SetAttribute(mod .. "-type1", "click")
                frame:SetAttribute(mod .. "-clickbutton1", proxy)
                frame:SetAttribute("*" .. mod .. "-type1", "click")
                frame:SetAttribute("*" .. mod .. "-clickbutton1", proxy)
            end)
            if ok then
                attachedAny = true
            end
        elseif not ModEnabled(mod) then
            ReleaseModifierIfOurs(frame, mod)
        end
    end

    if attachedAny then
        attachedFrames[frame] = true
        lastAppliedCount = lastAppliedCount + 1
        return true
    end

    return false
end

local function TryGlobal(name)
    local frame = _G[name]
    if frame then
        AttachTargetFix(frame)
    end
end

local function ApplyPartyFrames()
    for i = 1, 5 do
        TryGlobal("CompactPartyFrameMember" .. i)
        TryGlobal("PartyMemberFrame" .. i)
        -- pets
        TryGlobal("CompactPartyFramePet" .. i)
        TryGlobal("CompactRaidFramePet" .. i)
        TryGlobal("PartyMemberFrame" .. i .. "PetFrame")
        TryGlobal("PartyFrameMemberFrame" .. i .. "PetFrame")
        TryGlobal("PartyMemberFramePetFrame" .. i)
    end

    local party = _G.PartyFrame
    if party then
        for i = 1, 5 do
            TryGlobal("PartyFrameMemberFrame" .. i)
            local member = party["MemberFrame" .. i]
            if member then
                AttachTargetFix(member)
                if member.PetFrame then
                    AttachTargetFix(member.PetFrame)
                end
            end
        end
    end
end

local function ApplyRaidFrames()
    for i = 1, 40 do
        TryGlobal("CompactRaidFrame" .. i)
    end
    for g = 1, 8 do
        for m = 1, 5 do
            TryGlobal(string.format("CompactRaidGroup%dMember%d", g, m))
        end
    end
end

local function ApplyArenaFrames()
    for i = 1, 5 do
        TryGlobal("ArenaEnemyFrame" .. i)
        TryGlobal("ArenaPrepFrame" .. i)
        TryGlobal("CompactArenaFrameMember" .. i)
    end
end

local function ApplyCoreFrames()
    TryGlobal("PlayerFrame")
    TryGlobal("TargetFrame")
    TryGlobal("TargetFrameToT")
    TryGlobal("FocusFrame")
    TryGlobal("FocusFrameToT")
    TryGlobal("PetFrame")
    for i = 1, 5 do
        TryGlobal("Boss" .. i .. "TargetFrame")
    end
end

local function ApplyToClickCastFrames()
    if type(ClickCastFrames) ~= "table" then
        return
    end
    for frame in pairs(clickCastOld or ClickCastFrames) do
        AttachTargetFix(frame)
    end
end

local InstallClickCastHook

local function ApplyAll()
    if InCombatLockdown() then
        pendingApply = true
        return false, "combat"
    end

    lastAppliedCount = 0
    if InstallClickCastHook then
        InstallClickCastHook()
    end
    ApplyCoreFrames()
    ApplyPartyFrames()
    ApplyRaidFrames()
    ApplyArenaFrames()
    ApplyToClickCastFrames()
    for frame in pairs(attachedFrames) do
        AttachTargetFix(frame)
    end
    return true
end

-------------------------------------------------------------------------------
-- Click Casting profile fallback (Shift only)
-------------------------------------------------------------------------------

local function ModifierLabel(mod)
    if GetStringFromModifiers then
        return GetStringFromModifiers(mod or 0)
    end
end

local function IsShiftOnlyModifier(mod)
    local label = ModifierLabel(mod)
    if not label or label == "" then
        return false
    end
    local upper = label:upper()
    return upper:find("SHIFT", 1, true)
        and not upper:find("CTRL", 1, true)
        and not upper:find("CONTROL", 1, true)
        and not upper:find("ALT", 1, true)
        and not upper:find("META", 1, true)
end

local function ResolveShiftModifier()
    for mod = 0, 63 do
        if IsShiftOnlyModifier(mod) then
            return mod
        end
    end
    return 1
end

local function EnsureClickCastingBinding()
    if not db.shift then
        return true, "shift_disabled"
    end
    if not C_ClickBindings or not C_ClickBindings.GetProfileInfo or not C_ClickBindings.SetProfileByInfo
        or not Enum.ClickBindingType or not Enum.ClickBindingInteraction then
        return false, "api_unavailable"
    end
    if InCombatLockdown() then
        return false, "combat"
    end

    local profile = C_ClickBindings.GetProfileInfo()
    if type(profile) ~= "table" then
        return false, "no_profile"
    end

    for _, info in ipairs(profile) do
        local isLeft = info.button == "LeftButton" or info.button == "Button1"
        if isLeft and IsShiftOnlyModifier(info.modifiers or 0) then
            if info.type == Enum.ClickBindingType.Interaction
                and info.actionID == Enum.ClickBindingInteraction.Target then
                return true, "already_bound"
            end
            return false, "conflict"
        end
    end

    local shiftMod = ResolveShiftModifier()
    for _, info in ipairs(profile) do
        if info.type == Enum.ClickBindingType.Interaction
            and info.actionID == Enum.ClickBindingInteraction.Target
            and not info.button then
            info.button = "LeftButton"
            info.modifiers = shiftMod
            C_ClickBindings.SetProfileByInfo(profile)
            return true, "updated_default"
        end
    end

    profile[#profile + 1] = {
        type = Enum.ClickBindingType.Interaction,
        actionID = Enum.ClickBindingInteraction.Target,
        button = "LeftButton",
        modifiers = shiftMod,
    }
    C_ClickBindings.SetProfileByInfo(profile)
    return true, "added"
end

-------------------------------------------------------------------------------
-- Run / events
-------------------------------------------------------------------------------

local function RunFix(silent)
    local proxyOk, proxyReason = ApplyAll()
    local bindOk, bindReason = EnsureClickCastingBinding()

    if silent then
        return proxyOk, bindOk, bindReason, lastAppliedCount
    end

    if proxyOk then
        print(string.format(
            "|cff00ff00[%s]|r Applied secure proxy on %d unit button(s).",
            ADDON, lastAppliedCount))
        if lastAppliedCount > 80 then
            print("|cffff9900[" .. ADDON .. "]|r Unusually high frame count - please report via /shiftfix debug.")
        end
    elseif proxyReason == "combat" then
        print("|cffff9900[" .. ADDON .. "]|r In combat - queued, will retry when combat ends.")
        pendingApply = true
    end

    if bindOk and bindReason ~= "already_bound" and bindReason ~= "shift_disabled" then
        print("|cff00ff00[" .. ADDON .. "]|r Also registered Shift+Left -> Target in Click Casting.")
    elseif bindReason == "conflict" then
        print("|cffff9900[" .. ADDON .. "]|r Shift+Left already bound in Click Casting to another action.")
    end

    return proxyOk, bindOk, bindReason, lastAppliedCount
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_PET")

local petApplyQueued = false

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then
            pendingApply = false
            C_Timer.After(0, function() RunFix(true) end)
        end
        return
    end

    if event == "UNIT_PET" then
        -- Pet frames can be created/shown late; re-scan once (throttled).
        if petApplyQueued then
            return
        end
        if InCombatLockdown() then
            pendingApply = true
            return
        end
        petApplyQueued = true
        C_Timer.After(0.3, function()
            petApplyQueued = false
            if not InCombatLockdown() then
                ApplyPartyFrames()
                ApplyToClickCastFrames()
            else
                pendingApply = true
            end
        end)
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if InCombatLockdown() then
            pendingApply = true
            return
        end
        C_Timer.After(0, function()
            if not InCombatLockdown() then
                ApplyPartyFrames()
                ApplyRaidFrames()
                ApplyArenaFrames()
                ApplyToClickCastFrames()
            end
        end)
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function() RunFix(true) end)
        -- Re-apply after UI suites finish registering / overwriting click attrs.
        C_Timer.After(2, function() RunFix(true) end)
    end
end)

local function QueueAttach(frame)
    if not frame or IsNameplateRelatedFrame(frame) then
        return
    end
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    if attachedFrames[frame] then
        local needsWork = false
        for _, mod in ipairs(MODIFIERS) do
            if ModEnabled(mod) and not ModifierStillAttached(frame, mod) then
                needsWork = true
                break
            end
        end
        if not needsWork then
            return
        end
    end
    C_Timer.After(0, function()
        if not InCombatLockdown() and not IsNameplateRelatedFrame(frame) then
            AttachTargetFix(frame)
        end
    end)
end

InstallClickCastHook = function()
    if type(ClickCastFrames) ~= "table" then
        ClickCastFrames = {}
    end
    if ClickCastFrames == clickCastWrapper then
        return
    end

    local old = ClickCastFrames
    clickCastOld = old
    clickCastWrapper = setmetatable({}, {
        __newindex = function(_, frame, value)
            -- Write through so a previous wrapper (Ellesmere, Clique) still sees it.
            old[frame] = value
            if value and not InCombatLockdown() then
                QueueAttach(frame)
            end
        end,
        __index = function(_, frame)
            return old[frame]
        end,
        __pairs = function()
            return pairs(old)
        end,
    })
    ClickCastFrames = clickCastWrapper

    for frame, val in pairs(old) do
        if val then
            AttachTargetFix(frame)
        end
    end
end

-- Defer until AFTER CompactUnitFrame_SetUpFrame finishes UpdateAll (private auras).
if CompactUnitFrame_SetUpFrame then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", QueueAttach)
end
if CompactUnitFrame_SetUnit then
    hooksecurefunc("CompactUnitFrame_SetUnit", QueueAttach)
end

-- Wrap as early as possible so ElvUI/oUF/Clique registrations go through us.
if type(ClickCastFrames) ~= "table" then
    ClickCastFrames = {}
end
InstallClickCastHook()

-------------------------------------------------------------------------------
-- Debug
-------------------------------------------------------------------------------

local function DebugDump()
    print("|cff00ff00[" .. ADDON .. " debug]|r")
    local attached = 0
    for _ in pairs(attachedFrames) do
        attached = attached + 1
    end
    print("  Attached frames: " .. attached)
    print("  Last apply count: " .. lastAppliedCount)
    print("  In combat: " .. tostring(InCombatLockdown()))
    print("  ClickCastFrames wrap: " .. tostring(ClickCastFrames == clickCastWrapper))
    print("  Nameplates: never attached (Platynator/Plater safe)")

    if PlayerFrame and PlayerFrame.GetAttribute then
        print("  PlayerFrame shift-type1: " .. tostring(PlayerFrame:GetAttribute("shift-type1")))
        print("  PlayerFrame *shift-type1: " .. tostring(PlayerFrame:GetAttribute("*shift-type1")))
    end

    if C_ClickBindings and C_ClickBindings.GetBindingType then
        local shiftMod = ResolveShiftModifier()
        local btype, action = C_ClickBindings.GetBindingType("LeftButton", shiftMod)
        print("  GetBindingType(shift+left): type=" .. tostring(btype) .. " action=" .. tostring(action))
    end
end

-------------------------------------------------------------------------------
-- Settings UI
-------------------------------------------------------------------------------

local configFrame

local function ApplySettings()
    if not db then
        LoadDB()
    end

    if InCombatLockdown() then
        pendingApply = true
        print("|cffff9900[" .. ADDON .. "]|r Combat lockdown - settings will apply when combat ends.")
        return
    end

    for frame in pairs(attachedFrames) do
        for _, mod in ipairs(MODIFIERS) do
            if not ModEnabled(mod) then
                ReleaseModifierIfOurs(frame, mod)
            end
        end
    end

    ApplyAll()
end

local function CreateSettingsFrame()
    if not db then
        LoadDB()
    end

    if configFrame then
        configFrame:Show()
        return
    end

    configFrame = CreateFrame("Frame", "ShiftClickTargetFixConfig", UIParent, "BasicFrameTemplateWithInset")
    configFrame:SetSize(340, 280)
    configFrame:SetPoint("CENTER")
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
    configFrame:SetClampedToScreen(true)

    configFrame.title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    configFrame.title:SetPoint("TOP", 0, -25)
    configFrame.title:SetText("ShiftClickTargetFix Settings")

    local y = -50
    local function AddModifierToggle(mod, label, yOffset)
        local cb = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 25, yOffset)
        local text = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if not cb.Text then
            text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        end
        text:SetText(label)
        cb:SetChecked(db and db[mod])
        cb:SetScript("OnClick", function(self)
            if db then
                db[mod] = self:GetChecked()
            end
            ApplySettings()
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Toggle " .. label, 1, 1, 1)
            GameTooltip:AddLine("Hold the modifier + Left Click on unit frames to target.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
        return cb
    end

    AddModifierToggle("shift", "Enable Shift + Left-Click targeting", y)
    y = y - 28
    AddModifierToggle("ctrl", "Enable Ctrl + Left-Click targeting", y)
    y = y - 28
    AddModifierToggle("alt", "Enable Alt + Left-Click targeting", y)
    y = y - 28
    AddModifierToggle("combos", "Also allow combos (Alt+Shift, Ctrl+Shift, ...)", y)

    local info = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", 25, y - 20)
    info:SetWidth(290)
    info:SetText("Settings save automatically. Use /shiftfix apply to re-scan frames.")
    info:SetJustifyH("LEFT")
    info:SetTextColor(0.7, 0.7, 0.7)

    local ver = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ver:SetPoint("BOTTOMRIGHT", -10, 6)
    ver:SetText("v1.9.0-forever")
    ver:SetTextColor(0.5, 0.5, 0.5)
end

SLASH_SHIFTCLICKTARGETFIX1 = "/shiftfix"
SLASH_SHIFTCLICKTARGETFIX2 = "/shiftclicktargetfix"
SlashCmdList["SHIFTCLICKTARGETFIX"] = function(msg)
    msg = SafeTrim(msg):lower()
    if msg == "debug" then
        RunFix(true)
        DebugDump()
    elseif msg == "focus" then
        print("|cff00ff00[" .. ADDON .. "]|r Hover a unit frame; reporting in 3 seconds...")
        C_Timer.After(3, function()
            local f
            if GetMouseFoci then
                f = GetMouseFoci()[1]
            elseif GetMouseFocus then
                f = GetMouseFocus()
            end
            if not f then
                print("  no frame under mouse")
                return
            end
            local chain, cur = {}, f
            for _ = 1, 6 do
                if not cur then break end
                chain[#chain + 1] = FrameName(cur) ~= "" and FrameName(cur) or "<unnamed>"
                cur = cur.GetParent and cur:GetParent() or nil
            end
            print("  frame: " .. table.concat(chain, " < "))
            print("  unit: " .. tostring(GetUnitToken(f)))
            print("  allowed: " .. tostring(IsAllowedUnitButton(f)) .. "  nameplate: " .. tostring(IsNameplateRelatedFrame(f)))
            print("  attached: " .. tostring(attachedFrames[f] or false) .. "  shift-type1: " .. tostring(SafeGetAttribute(f, "shift-type1")))
        end)
    elseif msg == "apply" then
        print("|cff00ff00[" .. ADDON .. "]|r Applying fix...")
        C_Timer.After(0, function() RunFix(false) end)
    else
        CreateSettingsFrame()
    end
end
