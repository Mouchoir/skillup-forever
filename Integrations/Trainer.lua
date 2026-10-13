---@type string, SkillUpNamespace
local _, ns = ...

-- Per trainer update: which recipe each service teaches, and the one to train next.
---@type SkillUpTrainerState?
local state

-- The service tooltip carries the taught spell when the client exposes it; the
-- name is the fallback. Only an ID we have data for counts as a recipe.
---@param index integer
---@return integer?
local function TooltipRecipe(index)
	local data = C_TooltipInfo and C_TooltipInfo.GetTrainerService(index)
	local id = data and data.id
	if not (issecretvalue and issecretvalue(id)) and id and ns.RecipeData[id] then
		return id
	end
end

---@param services SkillUpTrainerService[]
---@return integer?
local function TrainerSkillLine(services)
	for _, service in pairs(services) do
		if service.recipeID then
			return ns.RecipeData[service.recipeID].skillLine
		end
	end
	local professions = ns.PlayerProfessions()
	for index in pairs(services) do
		local skillName = GetTrainerServiceSkillReq(index)
		for skillLine, profession in pairs(professions) do
			if profession.name == skillName then
				return skillLine
			end
		end
	end
end

---@param services SkillUpTrainerService[]
---@return table<integer, boolean>
local function Known(services)
	local known = {}
	for _, service in pairs(services) do
		if service.recipeID and service.kind == "used" then
			known[service.recipeID] = true
		end
	end
	return known
end

-- What this trainer would teach now that the player can pay for.
---@param services SkillUpTrainerService[]
---@return {recipeID: integer, fee: number}[]
local function Offers(services)
	local offers = {}
	local money = GetMoney()
	for index, service in pairs(services) do
		local fee = GetTrainerServiceCost(index)
		if service.recipeID and service.kind == "available" and fee <= money then
			offers[#offers + 1] = { recipeID = service.recipeID, fee = fee }
		end
	end
	return offers
end

-- What this trainer charges for each rank it still offers, kept under the cap the rank trains to. A rank
-- is the one row that is no recipe and wants the skill the bundled rank does; when two rows fit, neither
-- is trusted.
---@param skillLine integer
---@param services SkillUpTrainerService[]
local function NoteRanks(skillLine, services)
	for _, rank in ipairs(ns.TrainerRanks[skillLine] or {}) do
		local cap, reqSkill = rank[1], rank[3]
		local found, fits = nil, 0
		for index, service in pairs(services) do
			local _, required = GetTrainerServiceSkillReq(index)
			if not service.recipeID and not service.ambiguous and service.kind ~= "used" and required == reqSkill then
				found, fits = index, fits + 1
			end
		end
		if found and fits == 1 then
			ns.db.trainerRanks[skillLine] = ns.db.trainerRanks[skillLine] or {}
			ns.db.trainerRanks[skillLine][cap] = GetTrainerServiceCost(found)
		end
	end
end

---@return SkillUpTrainerService[]
local function Services()
	local services = {}
	for index = 1, GetNumTrainerServices() do
		local name, kind = GetTrainerServiceInfo(index)
		services[index] = { name = name, kind = kind, recipeID = TooltipRecipe(index) }
	end
	return services
end

---@return SkillUpTrainerState
local function BuildState(services)
	services = services or Services()
	local skillLine = TrainerSkillLine(services)
	local rank, maxRank, modifier = GetTrainerTradeskillRankValues()
	if not (skillLine and rank and maxRank) then
		return { services = services }
	end
	local names = ns.RecipeNames[skillLine] or {}
	for _, service in pairs(services) do
		if not service.recipeID and service.name then
			local match = names[service.name]
			service.ambiguous = match == false
			service.recipeID = match or nil
		end
	end
	-- Every recipe this trainer teaches, its fee and required skill, for routes
	-- planned away from it (bundled base fees miss discounts and Forever changes).
	local seen = ns.db.trainer[skillLine] or {}
	ns.db.trainer[skillLine] = seen
	-- A row that shows no skill requirement keeps the bundled one: recording 0 would plan to learn it at once.
	for index, service in pairs(services) do
		if service.recipeID then
			local _, required = GetTrainerServiceSkillReq(index)
			local bundled = ns.TrainerFees[service.recipeID]
			required = required or (bundled and bundled[2])
			if required then
				seen[service.recipeID] = { GetTrainerServiceCost(index), required }
			end
		end
	end
	NoteRanks(skillLine, services)
	ns.Changed("fees")
	modifier = modifier or 0
	local ctx = {
		skillLine = skillLine,
		base = rank,
		skill = rank + modifier,
		modifier = modifier,
		max = maxRank,
		capped = maxRank > 0 and rank >= maxRank,
	}
	return { services = services, ctx = ctx, best = ns.BestTraining(ctx, Known(services), Offers(services)) }
end

-- The recipe to train next wears the green arrow the bags put on an upgrade, 13 tall at its own aspect.
local MARKER_ATLAS, MARKER_HEIGHT = "bags-greenarrow", 13
---@type string?
local marker

---@return string
local function Marker()
	if not marker then
		marker = C_Texture.GetAtlasInfo(MARKER_ATLAS) and ns.Art.Markup(MARKER_ATLAS, MARKER_HEIGHT) .. " " or ""
	end
	return marker
end

-- ClassTrainerSkillButtonTemplate's "Requires:" line starts 48 in (the icon at 6, 36 wide, then 6).
-- The row text sits right of it, 8 from the button's right edge, and ends in "..." rather than reach it.
local REQUIREMENT_LEFT, GAP, RIGHT = 48, 6, 8

---@param button SkillUpTrainerButton
---@param elementData SkillUpTrainerElement
local function Decorate(button, elementData)
	local text = button.SkillUpText
	if text then
		text:Hide()
	end
	elementData = elementData and (elementData.data or elementData)
	local index = elementData and elementData.skillIndex
	-- No state while a rebuild is pending; the rebuild redecorates.
	local current = state
	local service = current and index and current.services[index]
	if not (current and service and current.ctx and (service.recipeID or service.ambiguous)) then
		return
	end
	if not text then
		text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("BOTTOMRIGHT", -RIGHT, 6)
		text:SetJustifyH("RIGHT")
		text:SetWordWrap(false)
		button.SkillUpText = text
	end
	local requirement = button.subText
	local room = button:GetWidth()
		- RIGHT
		- REQUIREMENT_LEFT
		- math.min(requirement:GetStringWidth(), requirement:GetWidth())
		- GAP
	if room < 1 then
		return
	end
	text:SetWidth(room)
	if service.recipeID then
		local d = ns.Describe({ recipeID = service.recipeID, learned = service.kind == "used" }, current.ctx)
		local best = service.recipeID == current.best and Marker() or ""
		text:SetText(best .. ns.FormatRow(d))
		text:SetTextColor(ns.RowColor(d):GetRGB())
	else
		text:SetText("?")
		text:SetTextColor(ns.COLORS.unknown:GetRGB())
	end
	text:Show()
end

local function DecorateAll()
	ClassTrainerFrame.ScrollBox:ForEachFrame(function(button)
		Decorate(button, button:GetElementData())
	end)
	local step = GetTrainerServiceStepIndex()
	if step and ClassTrainerFrame.skillStepButton:IsShown() then
		Decorate(ClassTrainerFrame.skillStepButton, { skillIndex = step })
	end
end

-- Blizzard updates once per service name that arrives, and redraws the buttons
-- inside each update; drop the old state at once and rebuild once, next frame.
local pending = false
local function RefreshTrainer()
	state = nil
	if pending or not ClassTrainerFrame:IsShown() then
		return
	end
	pending = true
	C_Timer.After(0, function()
		pending = false
		local tradeskill = C_Trainer.GetTrainerType() == Enum.TrainerType.Tradeskills
		local shown = tradeskill and ClassTrainerFrame:IsShown()
		local services = shown and Services() or nil
		if services then
			-- A trainer for a profession with a route still ahead starts tracking it on its own.
			ns.AutoTrack(TrainerSkillLine(services))
		end
		state = ns.db.showTrainer and services and BuildState(services) or nil
		DecorateAll()
	end)
end

function ns.AttachTrainer()
	hooksecurefunc("ClassTrainerFrame_InitServiceButton", Decorate)
	hooksecurefunc("ClassTrainerFrame_Update", RefreshTrainer)
	ns.WhenStale("trainer", RefreshTrainer)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_MONEY")
	events:RegisterEvent("TRAINER_CLOSED")
	events:SetScript("OnEvent", RefreshTrainer)
end
