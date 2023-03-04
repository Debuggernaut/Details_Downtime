-- This addon was based on Details! Explosive Orbs plugin

local addon, Engine = ...
local EO = LibStub("AceAddon-3.0"):NewAddon(addon, "AceEvent-3.0", "AceHook-3.0")
local L = Engine.L

Engine.Core = EO
_G[addon] = Engine

-- Lua functions
local _G = _G
local format, ipairs, pairs, select, strmatch, tonumber, type = format, ipairs, pairs, select, strmatch, tonumber, type
local bit_band = bit.band

-- WoW API / Variables
local C_ChallengeMode_GetActiveKeystoneInfo = C_ChallengeMode.GetActiveKeystoneInfo
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local CreateFrame = CreateFrame
local GetAddOnMetadata = GetAddOnMetadata
local UnitGUID = UnitGUID

local tContains = tContains

local COMBATLOG_OBJECT_TYPE_PET = COMBATLOG_OBJECT_TYPE_PET

local Details = _G.Details

-- GLOBALS: ExplosiveOrbsLog


--Seconds between print messages
EO.PRINT_SPAM_COOLDOWN = 1.0

--Time it'll spam while you're idle before leaving you alone
EO.SPAM_TIME_LIMIT = 2.5

EO.debug = false
EO.lastPoll = 0
EO.lastSpam = 0
EO.orbID = 120651 -- Explosive
EO.CustomDisplay = {
	name = L["Downtime"],
	icon = 133911,
	source = false,
	attribute = false,
	spellid = false,
	target = false,
	author = "Bernycinders-Thrall",
	desc = L["Cast time lost to mechanics, etc"],
	script_version = 13,
	script = [[
        local Combat, CustomContainer, Instance = ...
        local total, top, amount = 0, 0, 0

        if _G.Details_Downtime then
            local CombatNumber = Combat:GetCombatNumber()
            local Container = Combat:GetContainer(DETAILS_ATTRIBUTE_DAMAGE)
            for _, Actor in Container:ListActors() do
                --Only record data for yourself
                if Actor:guid() == UnitGUID("player") then
                    local downtime, pct = _G.Details_Downtime:GetRecord(CombatNumber, Actor:guid())
                    CustomContainer:AddValue(Actor, downtime)
                end
            end

            total, top = CustomContainer:GetTotalAndHighestValue()
            amount = CustomContainer:GetNumActors()
        end

        return total, top, amount
    ]],
	tooltip = [[
        -- local Actor, Combat, Instance = ...
        -- local GameCooltip = GameCooltip

        -- if _G.Details_Downtime then
        --     local actorName = Actor:name()
        --     local Actor = Combat:GetContainer(DETAILS_ATTRIBUTE_DAMAGE):GetActor(actorName)
        --     if not Actor then return end

        --     local sortedList = {}
        --     local orbName = _G.Details_Downtime:RequireOrbName()
        --     local Container = Combat:GetContainer(DETAILS_ATTRIBUTE_DAMAGE)

        --     for spellID, spellTable in pairs(Actor:GetSpellList()) do
        --         local amount = spellTable.targets[orbName]
        --         if amount then
        --             tinsert(sortedList, {spellID, amount})
        --         end
        --     end

        --     -- handle pet
        --     for _, petName in ipairs(Actor.pets) do
        --         local petActor = Container:GetActor(petName)
        --         for spellID, spellTable in pairs(petActor:GetSpellList()) do
        --             local amount = spellTable.targets[orbName]
        --             if amount then
        --                 tinsert(sortedList, {spellID, amount, petName})
        --             end
        --         end
        --     end

        --     sort(sortedList, Details.Sort2)

        --     local format_func = Details:GetCurrentToKFunction()
        --     for _, tbl in ipairs(sortedList) do
        --         local spellID, amount, petName = unpack(tbl)
        --         local spellName, _, spellIcon = Details.GetSpellInfo(spellID)
        --         if petName then
        --             spellName = spellName .. ' (' .. petName .. ')'
        --         end

        --         GameCooltip:AddLine(spellName, format_func(_, amount))
        --         Details:AddTooltipBackgroundStatusbar()
        --         GameCooltip:AddIcon(spellIcon, 1, 1, _detalhes.tooltip.line_height, _detalhes.tooltip.line_height)
        --     end
        -- end
    ]],
	total_script = [[
        local value, top, total, Combat, Instance, Actor = ...

        if _G.Details_Downtime then
            return _G.Details_Downtime:GetDisplayText(Combat:GetCombatNumber(), Actor.my_actor:guid())
        end
        return ""
    ]],
	percent_script = [[
		return ""
	]]
}

-- Public APIs

local template = L["Downtime: "] .. "%.2fs"
local displayTemplate = {
	-- keeping this around in case it's useful later
	-- http://thecodelesscode.com/case/41
	[true] = {
		[true] = template,
		[false] = template
	},
	[false] = {
		[true] = template,
		[false] = template
	}
}

function Engine:GetRecord(combatID, playerGUID)
	if EO.db[combatID] and EO.db[combatID][playerGUID] then
		return EO.db[combatID][playerGUID].downtime or 0, EO.db[combatID][playerGUID].hit or 0
	end
	return 0, 0
end

function Engine:GetDisplayText(combatID, playerGUID)
	if EO.db[combatID] and EO.db[combatID][playerGUID] then
		return format(
			displayTemplate[EO.plugin.db.useShortText][EO.plugin.db.onlyShowHit],
			EO.db[combatID][playerGUID].downtime or 0,
			EO.db[combatID][playerGUID].hit or 0
		)
	end
	return format(displayTemplate[EO.plugin.db.useShortText][EO.plugin.db.onlyShowHit], 0, 0)
end

function Engine:FormatDisplayText(downtime, hit)
	return format(displayTemplate[EO.plugin.db.useShortText][EO.plugin.db.onlyShowHit], downtime or 0, hit or 0)
end

function Engine:RequireOrbName()
	if not EO.orbName then
		EO.orbName = Details:GetSourceFromNpcId(EO.orbID)
	end
	return EO.orbName
end

-- Private Functions

function EO:Debug(...)
	if self.debug then
		_G.DEFAULT_CHAT_FRAME:AddMessage("|cFF70B8FFDetails Downtime:|r " .. format(...))
	end
end

function EO:ParseNPCID(unitGUID)
	return tonumber(strmatch(unitGUID or "", "Creature%-.-%-.-%-.-%-.-%-(.-)%-") or "")
end

-- debug:
-- /dump _G.Details_Downtime.Core.currentCombat.runningTotal

local function spamWhenIdle()
	local now = GetTime()

	if (EO.lastStoppedCasting == nil) then
		return
	end

	if (now - EO.lastStoppedCasting) > EO.SPAM_TIME_LIMIT then
		return
	end

	if (now - EO.lastSpam) > EO.PRINT_SPAM_COOLDOWN then
		print("It's",GetTime(),"  Ask yourself: Do you really want to be the kind of player who's got endless time to run out of mechanics but 'can't afford' to get in a little more DPS?")
		EO.lastSpam = now
	end
end

function Details_Downtime_Casting()
	local casting = true

	local spell, _, _, _, endTimeMs = UnitCastingInfo("player")
	local gcdStart, gcdDur, _, _ = GetSpellCooldown(61304)

	if (gcdStart == 0 and endTimeMs == nil) then
		casting = false
	end

	return casting;
end

function Details_Downtime_CheckIdle(threshold)
	local casting = Details_Downtime_Casting()

	if (EO.lastStoppedCasting == nil) then
		return false
	end

	if (casting ~= true) then
		return (GetTime() - EO.lastStoppedCasting) > threshold
	else
		return false
	end
end

-- Runs roughly once every 100 milliseconds
-- Will record any time period where it sees you not casting twice in a row
local function pollStatus()
	if not EO.currentCombat then
		--EO.lastPoll = nil
		--EO.wasCasting = true
		C_Timer.After(0.1, pollStatus)
		return
	end

	local now = GetTime()
	local casting = true

	if EO.lastPoll ~= nil then
		if not EO.runningTotal then
			EO.runningTotal = 0
			EO.wasCasting = true
			EO.lastPoll = now
		end

		local duration = now - EO.lastPoll

		casting = Details_Downtime_Casting()

		if EO.wasCasting == true and casting == false then
			EO.lastStoppedCasting = now
		end
		
		if EO.wasCasting == false and casting == true then
			-- If you see this message, there was at least a blip where you weren't casting
			--print("Together we are going to stand up to draconic billionaires!  We will not sit idle!")
		end

		if (EO.wasCasting == false and casting == false) then
			spamWhenIdle()
			EO.runningTotal = EO.runningTotal + duration
			EO:RecordDowntime(UnitGUID("player"), duration)
		end

		EO.wasCasting = casting

	end

	EO.lastPoll = now
	C_Timer.After(0.1, pollStatus)
end

local function targetChanged(self, _, unitID)
	local targetGUID = UnitGUID(unitID .. "target")
	if not targetGUID then
		return
	end

	local npcID = EO:ParseNPCID(targetGUID)
	if npcID == EO.orbID then
		-- record pet's target to its owner
		EO:RecordTarget(UnitGUID(self.unitID), targetGUID)
	end
end

function EO:COMBAT_LOG_EVENT_UNFILTERED()
	-- local _, subEvent, _, sourceGUID, sourceName, sourceFlag, _, destGUID = CombatLogGetCurrentEventInfo()
	-- if
	-- 	(subEvent == "SPELL_DAMAGE" or subEvent == "RANGE_DAMAGE" or subEvent == "SWING_DAMAGE" or
	-- 		subEvent == "SPELL_PERIODIC_DAMAGE" or
	-- 		subEvent == "SPELL_BUILDING_DAMAGE")
	--  then
	-- 	local npcID = self:ParseNPCID(destGUID)
	-- 	if npcID == self.orbID then
	-- 		if bit_band(sourceFlag, COMBATLOG_OBJECT_TYPE_PET) > 0 then
	-- 			-- source is pet, don't track guardian which is automaton
	-- 			local Combat = Details:GetCombat(0)
	-- 			if Combat then
	-- 				local Container = Combat:GetContainer(_G.DETAILS_ATTRIBUTE_DAMAGE)
	-- 				local ownerActor = select(2, Container:PegarCombatente(sourceGUID, sourceName, sourceFlag, true))
	-- 				if ownerActor then
	-- 					-- Details implements two cache method of pet and its owner,
	-- 					-- one is in parser which is shared inside parser (damage_cache_petsOwners),
	-- 					-- it will be wiped in :ClearParserCache, but I have no idea when,
	-- 					-- the other is in container,
	-- 					-- which :PegarCombatente will try to fetch owner from it first,
	-- 					-- so in this case, simply call :PegarCombatente and use its cache,
	-- 					-- and no need to implement myself like parser
	-- 					sourceGUID = ownerActor:guid()
	-- 				end
	-- 			end
	-- 		end
	-- 		EO:RecordHit(sourceGUID, destGUID)
	-- 	end
	-- end
end

function EO:RecordDowntime(unitGUID, downtimeDuration)
	if not self.currentCombat then
		return
	end

	-- self:Debug("%s target %s in combat %s", unitGUID, targetGUID, self.current)

	if not self.db[self.currentCombat] then
		self.db[self.currentCombat] = {}
	end
	if not self.db[self.currentCombat][unitGUID] then
		self.db[self.currentCombat][unitGUID] = {}
	end

	self.db[self.currentCombat][unitGUID].downtime =
		(self.db[self.currentCombat][unitGUID].downtime or 0) + downtimeDuration

	-- -- update overall
	-- if not self.db[self.overall] then
	-- 	self.db[self.overall] = {}
	-- end
	-- if not self.db[self.overall][unitGUID] then
	-- 	self.db[self.overall][unitGUID] = {}
	-- end

	-- self.db[self.overall][unitGUID].downtime = (self.db[self.overall][unitGUID].downtime or 0) + downtimeDuration
end

function EO:RecordHit(unitGUID, targetGUID)
	-- if not self.currentCombat then return end
	-- -- self:Debug("%s hit %s in combat %s", unitGUID, targetGUID, self.current)
	-- if not self.db[self.currentCombat] then self.db[self.current] = {} end
	-- if not self.db[self.currentCombat][unitGUID] then self.db[self.currentCombat][unitGUID] = {} end
	-- if not self.db[self.currentCombat][unitGUID][targetGUID] then self.db[self.currentCombat][unitGUID][targetGUID] = 0 end
	-- if self.db[self.currentCombat][unitGUID][targetGUID] ~= 2 and self.db[self.currentCombat][unitGUID][targetGUID] ~= 3 then
	--     self.db[self.currentCombat][unitGUID][targetGUID] = self.db[self.currentCombat][unitGUID][targetGUID] + 2
	--     self.db[self.currentCombat][unitGUID].hit = (self.db[self.currentCombat][unitGUID].hit or 0) + 1
	--     -- update overall
	--     if not self.db[self.overall] then self.db[self.overall] = {} end
	--     if not self.db[self.overall][unitGUID] then self.db[self.overall][unitGUID] = {} end
	--     self.db[self.overall][unitGUID].hit = (self.db[self.overall][unitGUID].hit or 0) + 1
	-- end
end

function EO:OnDetailsEvent(event, combat)
	if event == "COMBAT_PLAYER_ENTER" then
		EO.currentCombat = combat:GetCombatNumber()
		--EO.overall = Details:GetCombat(-1):GetCombatNumber()
		EO:Debug("COMBAT_PLAYER_ENTER: %s", EO.currentCombat)
	elseif event == "COMBAT_PLAYER_LEAVE" then
		EO.currentCombat = combat:GetCombatNumber()
		EO:Debug("COMBAT_PLAYER_LEAVE: %s", EO.currentCombat)

		if not EO.currentCombat or not EO.db[EO.currentCombat] then
			return
		end
		-- for _, list in pairs(EO.db[EO.currentCombat]) do
		-- 	for key in pairs(list) do
		-- 		if key ~= "target" and key ~= "hit" then
		-- 			list[key] = nil
		-- 		end
		-- 	end
		-- end
		EO.db[EO.currentCombat].runID = select(2, combat:IsMythicDungeon())
		EO.currentCombat = nil
	elseif event == "DETAILS_DATA_RESET" then
		EO:Debug("DETAILS_DATA_RESET")
	--EO.overall = Details:GetCombat(-1):GetCombatNumber()
	--EO:CleanDiscardCombat()
	end
end

function EO:LoadHooks()
	--self:SecureHook(_G.DetailsMythicPlusFrame, 'MergeSegmentsOnEnd')
	--self:SecureHook(_G.DetailsMythicPlusFrame, 'MergeTrashCleanup')
	--self:SecureHook(_G.DetailsMythicPlusFrame, 'MergeRemainingTrashAfterAllBossesDone')

	--self:SecureHook(Details.historico, 'resetar_overall', 'OnResetOverall')
	--self.overall = Details:GetCombat(-1):GetCombatNumber()

	Details:InstallCustomObject(self.CustomDisplay)
	--Details:InstallCustomObject(self.CustomDisplayOverall)
	--self:CleanDiscardCombat()
end

do
	local plugin

	local defaults = {
		onlyShowHit = false,
		useShortText = false
	}

	local buildOptionsPanel = function()
		local frame = plugin:CreatePluginOptionsFrame("DetailsDowntimeOptionsWindow", "Details! Explosive Orbs Options", 1)

		local menu = {
			{
				type = "toggle",
				name = L["Only Show Hit"],
				desc = L["Only show the hit of Explosive Orbs, without target."],
				get = function()
					return plugin.db.onlyShowHit
				end,
				set = function(_, _, v)
					plugin.db.onlyShowHit = v
				end
			},
			{
				type = "toggle",
				name = L["Use Short Text"],
				desc = L["Use short text for Explosive Orbs."],
				get = function()
					return plugin.db.useShortText
				end,
				set = function(_, _, v)
					plugin.db.useShortText = v
				end
			}
		}

		local framework = plugin:GetFramework()
		local options_text_template = framework:GetTemplate("font", "OPTIONS_FONT_TEMPLATE")
		local options_dropdown_template = framework:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE")
		local options_switch_template = framework:GetTemplate("switch", "OPTIONS_CHECKBOX_TEMPLATE")
		local options_slider_template = framework:GetTemplate("slider", "OPTIONS_SLIDER_TEMPLATE")
		local options_button_template = framework:GetTemplate("button", "OPTIONS_BUTTON_TEMPLATE")

		framework:BuildMenu(
			frame,
			menu,
			15,
			-75,
			360,
			true,
			options_text_template,
			options_dropdown_template,
			options_switch_template,
			true,
			options_slider_template,
			options_button_template
		)
	end

	local OpenOptionsPanel = function()
		if not _G.DetailsExplosiveOrbsOptionsWindow then
			buildOptionsPanel()
		end

		_G.DetailsExplosiveOrbsOptionsWindow:Show()
	end

	local OnDetailsEvent = function(_, event, ...)
		if event == "DETAILS_STARTED" then
			EO:LoadHooks()
			return
		elseif event == "PLUGIN_DISABLED" then
			return
		elseif event == "PLUGIN_ENABLED" then
			return
		end

		EO:OnDetailsEvent(event, ...)
	end

	function EO:InstallPlugin()
		local version = GetAddOnMetadata(addon, "Version")

		plugin = Details:NewPluginObject("Details_Downtime", _G.DETAILSPLUGIN_ALWAYSENABLED)
		plugin.OpenOptionsPanel = OpenOptionsPanel
		plugin.OnDetailsEvent = OnDetailsEvent
		self.plugin = plugin

		local MINIMAL_DETAILS_VERSION_REQUIRED = 20
		Details:InstallPlugin(
			"TOOLBAR",
			L["Downtime"],
			133911,
			plugin,
			"DETAILS_PLUGIN_DOWNTIME",
			MINIMAL_DETAILS_VERSION_REQUIRED,
			"Bernycinders-Thrall",
			version,
			defaults
		)

		Details:RegisterEvent(plugin, "COMBAT_PLAYER_ENTER")
		Details:RegisterEvent(plugin, "COMBAT_PLAYER_LEAVE")
		--todo: spellcast started/failed
		Details:RegisterEvent(plugin, "DETAILS_DATA_RESET")
	end
end

function EO:OnInitialize()
	-- load database
	self.db = DowntimeLog or {}
	DowntimeLog = self.db

	-- -- unit event frames
	-- self.eventFrames = {}
	-- for i = 1, 5 do
	--     self.eventFrames[i] = CreateFrame('frame')
	--     self.eventFrames[i]:SetScript('OnEvent', targetChanged)
	--     self.eventFrames[i].unitID = (i == 5 and 'player' or ('party' .. i))
	-- end

	--self:RegisterEvent('PLAYER_ENTERING_WORLD', 'CheckAffix')
	--self:RegisterEvent('CHALLENGE_MODE_START', 'CheckAffix')

	pollStatus()

	self:InstallPlugin()
end
