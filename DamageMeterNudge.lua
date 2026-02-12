-- DamageMeterNudge (Minimal Unlock)
-- v1.2.2: Removes all nudging/anchoring to avoid breaking Edit Mode sizing.
-- This addon now simply UNLOCKS Blizzard's Damage Meter windows so Edit Mode can move them closer to screen edges.

local ADDON_NAME = ...

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(("|cff00d1ff%s|r: %s"):format(ADDON_NAME, msg))
    end
end

-- Tracks whether the user asked for clamping (rare; default is unlocked)
local clampEnabled = false

-- Midnight combat/instance restrictions:
-- Do NOT attempt to change protected frame state during combat or while a Mythic+ run is active.
local pendingUnlock = false

local function IsMythicPlusActive()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
end

local function CanApplyNow()
    if InCombatLockdown and InCombatLockdown() then return false end
    if IsMythicPlusActive() then return false end
    return true
end

local function SetInsets(frame, left, right, top, bottom)
    if frame.SetClampRectInsets then
        frame:SetClampRectInsets(left, right, top, bottom)
    end
    if frame.SetRestrictedInsets then
        frame:SetRestrictedInsets(left, right, top, bottom)
    end
end

local function ApplyClamp(frame, enabled)
    if not frame or frame == UIParent then return end

    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(enabled and true or false)
    end

    if enabled then
        -- Best-effort restore to "normal" insets.
        SetInsets(frame, 0, 0, 0, 0)
    else
        -- Effectively removes clamp/restriction so Edit Mode can push it further.
        SetInsets(frame, -2000, -2000, -2000, -2000)
    end
end

local function ApplyClampToChain(frame, enabled)
    if not frame then return end

    ApplyClamp(frame, enabled)

    -- Also apply to parent chain because Blizzard sometimes clamps higher up.
    local p = frame:GetParent()
    local i = 0
    while p and p ~= UIParent and i < 12 do
        ApplyClamp(p, enabled)
        p = p:GetParent()
        i = i + 1
    end
end

local function GetWindows()
    -- Blizzard names may change; we try the most likely ones.
    local windows = {
        _G.DamageMeterSessionWindow1,
        _G.DamageMeterSessionWindow2,
        _G.DamageMeterSessionWindow3,
        _G.DamageMeter, -- fallback / container
    }

    -- Deduplicate
    local seen, out = {}, {}
    for _, f in ipairs(windows) do
        if f and not seen[f] then
            seen[f] = true
            table.insert(out, f)
        end
    end
    return out
end

local function UnlockNow()
    local windows = GetWindows()
    if #windows == 0 then
        return false
    end

    for _, f in ipairs(windows) do
        ApplyClampToChain(f, clampEnabled)
    end
    return true
end

local function UnlockSoon()
    C_Timer.After(0, UnlockNow)
    C_Timer.After(0.25, UnlockNow)
    C_Timer.After(1.0, UnlockNow)
end


local function QueueUnlock()
    pendingUnlock = true
end

local function TryUnlockSoon()
    if not CanApplyNow() then
        QueueUnlock()
        return
    end
    pendingUnlock = false
    UnlockSoon()
end

-- Slash commands
SLASH_DMUNLOCK1 = "/dmunlock"
SlashCmdList.DMUNLOCK = function()
    if not CanApplyNow() then
        QueueUnlock()
        Print(IsMythicPlusActive() and "Queued: will unlock after the Mythic+ run ends." or "Queued: will unlock after combat ends.")
        return
    end
    if UnlockNow() then
        Print(clampEnabled and "Clamp is ON (default Blizzard behaviour)." or "Unlocked Damage Meter windows (Edit Mode can move them further).")
    else
        Print("Damage Meter windows not found yet. Try again after opening the Damage Meter once.")
    end
end

SLASH_DMCLAMP1 = "/dmclamp"
SlashCmdList.DMCLAMP = function(input)
    input = (input or ""):match("^%s*(.-)%s*$"):lower()

    if input == "on" or input == "true" or input == "1" then
        clampEnabled = true
        TryUnlockSoon()
        Print("Clamp: ON")
    elseif input == "off" or input == "false" or input == "0" or input == "" then
        clampEnabled = false
        TryUnlockSoon()
        Print("Clamp: OFF (unlocked)")
    else
        Print("Usage: /dmclamp on|off")
    end
end

-- Backwards-compat commands (so old users don't get confused)
SLASH_DMN1 = "/dmnudge"
SlashCmdList.DMN = function(input)
    input = (input or ""):match("^%s*(.-)%s*$"):lower()
    if input == "apply" or input == "" then
        SlashCmdList.DMUNLOCK()
        if input == "" then
            Print("Minimal mode: use /dmunlock and /dmclamp on|off")
        end
    else
        Print("Minimal mode: nudging UI/offsets were removed. Use /dmunlock and /dmclamp on|off")
    end
end

-- Auto-unlock on login / world / edit mode refreshes (doesn't move or re-anchor anything)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
ev:RegisterEvent("UI_SCALE_CHANGED")

-- Combat + Mythic+ safety gates
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("CHALLENGE_MODE_COMPLETED")
ev:RegisterEvent("CHALLENGE_MODE_RESET")

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" or event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        if pendingUnlock then
            TryUnlockSoon()
        end
        return
    end

    -- For normal UI refresh/login events, attempt immediately (or queue if blocked)
    TryUnlockSoon()
end)