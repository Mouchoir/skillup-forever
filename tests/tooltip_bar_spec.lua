-- Run from the repository root: luajit tests/tooltip_bar_spec.lua
-- The recipe tooltip's skill bar (#161). Run from our handler, the tooltip's own line count and line height are
-- secret, and Blizzard's GameTooltip_InsertFrame does arithmetic on them: "attempt to perform arithmetic on a
-- secret number value (execution tainted by 'SkillUpForever')", once per hover. The bar is placed without it,
-- and without reading anything the tooltip owns.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- A secret number: any arithmetic or comparison on it raises, as the client's does.
local secret = newproxy(true)
local function Refuse()
	error("attempt to perform arithmetic on a secret number value (execution tainted by 'SkillUpForever')", 2)
end
for _, event in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__lt", "__le", "__concat" }) do
	getmetatable(secret)[event] = Refuse
end

-- A region that records its anchors, parent and visibility; any other method is accepted and ignored.
local function Region(name)
	local region = { name = name, points = {}, shown = true, scripts = {} }
	return setmetatable(region, {
		__index = function(_, key)
			if key == "SetPoint" then
				return function(self, ...)
					self.points[#self.points + 1] = { ... }
				end
			elseif key == "ClearAllPoints" then
				return function(self)
					self.points = {}
				end
			elseif key == "SetParent" then
				return function(self, parent)
					self.parent = parent
				end
			elseif key == "Show" then
				return function(self)
					self.shown = true
				end
			elseif key == "Hide" then
				return function(self)
					self.shown = false
				end
			elseif key == "SetShown" then
				return function(self, shown)
					self.shown = shown and true or false
				end
			elseif key == "IsShown" then
				return function(self)
					return self.shown
				end
			elseif key == "CreateTexture" or key == "CreateFontString" then
				return function()
					return Region()
				end
			end
			return function() end
		end,
	})
end

-- GameTooltip: its lines are named regions, and everything it would report about itself is secret.
local env
local lines, hooks = {}, {}
local tooltip = Region("GameTooltip")
function tooltip.SetOwner()
	lines = {}
	for _, fn in ipairs(hooks.OnTooltipCleared or {}) do
		fn(tooltip)
	end
end
function tooltip.AddLine(_, text)
	lines[#lines + 1] = text
	env["GameTooltipTextLeft" .. #lines] = env["GameTooltipTextLeft" .. #lines] or Region("line " .. #lines)
end
function tooltip.AddDoubleLine(self, text)
	self:AddLine(text)
end
function tooltip.HookScript(_, script, fn)
	hooks[script] = hooks[script] or {}
	table.insert(hooks[script], fn)
end
function tooltip.NumLines()
	return secret
end
function tooltip.GetCustomLineSpacing()
	return 2
end
function tooltip.GetMinimumWidth()
	return secret
end
function tooltip.GetLeftLine()
	return Region()
end
function tooltip.SetMinimumWidth(self, width)
	self.minimumWidth = width
end

local color = {
	GetRGB = function()
		return 1, 1, 1
	end,
}
env = setmetatable({
	GameTooltip = tooltip,
	UIParent = Region("UIParent"),
	-- What Blizzard's own helper does with the tooltip's line count, which is where the player's error came from.
	GameTooltip_InsertFrame = function(owner, frame, padding)
		local current = owner:NumLines()
		frame:SetPoint("TOPLEFT", owner:GetLeftLine(current + 1), "TOPLEFT", 0, -padding)
	end,
	GameTooltip_SetTitle = function(owner, text)
		owner:AddLine(text)
	end,
	GameTooltip_AddColoredLine = function(owner, text)
		owner:AddLine(text)
	end,
	GameTooltip_AddDisabledLine = function(owner, text)
		owner:AddLine(text)
	end,
	GameTooltip_AddBlankLineToTooltip = function(owner)
		owner:AddLine(" ")
	end,
	Professions = {
		GetHighestLearnedRecipe = function() end,
	},
	RED_FONT_COLOR = color,
	HIGHLIGHT_FONT_COLOR = color,
	C_CurrencyInfo = {
		GetCoinTextureString = function(copper)
			return tostring(copper)
		end,
	},
}, { __index = _G })
env._G = env
-- Every frame the file makes, to find the bar among them.
local made = {}
env.CreateFrame = function()
	local frame = Region()
	made[#made + 1] = frame
	return frame
end

local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	db = { showTooltip = true, showCost = false },
	COLORS = { orange = color, yellow = color, green = color, grey = color, red = color },
	Art = { Fit = function() end },
	Usable = function(frame)
		return frame ~= nil
	end,
	SkillContext = function()
		return { skill = 40 }
	end,
	Describe = function()
		return { thresholds = { 1, 30, 45, 60 }, chance = 0.5, color = "yellow" }
	end,
}
setfenv(assert(loadfile("UI/Tooltip.lua")), env)("SkillUpForever", ns)

local row = Region("row")
local data = { recipeInfo = { recipeID = 3275, name = "Linen Bandage" } }

-- The hover that failed: drawn with no error, and the bar sits on the lines after the title and skill range.
ns:ShowRecipeTooltip(row, data)
equal(lines[1], "Linen Bandage", "the title is the first line")
equal(lines[2], "Skill range starts at 1", "the skill range is the second")
equal(lines[3], " ", "blank lines follow for the bar")
equal(lines[6], " ", "four of them, enough for the bar and its labels")
equal(lines[7], "Skill-up chance: 50%", "and the chance comes after them")

-- The bar is the one frame anchored to the first blank line.
local anchored = {}
for _, frame in ipairs(made) do
	for _, point in ipairs(frame.points) do
		if point[2] == env.GameTooltipTextLeft3 then
			anchored[#anchored + 1] = frame
		end
	end
end
equal(#anchored, 1, "one frame is anchored to the first blank line")
local bar = anchored[1]
equal(bar.points[1][1], "TOPLEFT", "by its top left")
equal(bar.points[1][5], -4, "4 pixels below the line's top")
equal(bar.parent, tooltip, "parented to the tooltip, so it hides with it")
equal(bar.shown, true, "and shown")
equal(tooltip.minimumWidth, 250, "the tooltip is at least as wide as the bar")

-- A tooltip cleared for something else, or the next recipe without skill data, drops the bar.
tooltip:SetOwner(Region("item"))
equal(bar.shown, false, "a cleared tooltip hides the bar")
ns:ShowRecipeTooltip(row, data)
equal(bar.shown, true, "the next recipe shows it again")
ns.Describe = function()
	return {}
end
ns:ShowRecipeTooltip(row, data)
equal(bar.shown, false, "a recipe with no skill data shows no bar")
equal(lines[2], "No skill data for this recipe yet.", "but says why")

print(("tooltip_bar_spec: %d checks passed"):format(checks))
