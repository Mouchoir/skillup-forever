-- Run from the repository root: luajit tests/tooltip_stale_spec.lua
-- A route row's tooltip is redrawn when the sources change: a vendor read that finishes after the first
-- hover, with the row still under the mouse, draws its tooltip again on the game's next update.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local THREAD, SELLER = 2321, 301

-- A frame or region that records its anchors, text and visibility; anything else is accepted and ignored.
local function Region()
	local methods = {
		SetPoint = function(self, ...)
			self.points[#self.points + 1] = { ... }
		end,
		ClearAllPoints = function(self)
			self.points = {}
		end,
		SetText = function(self, text)
			self.text = text
		end,
		SetShown = function(self, shown)
			self.shown = shown
		end,
		SetScript = function(self, name, script)
			self.scripts[name] = script
		end,
		GetWidth = function()
			return 300
		end,
		GetStringHeight = function()
			return 12
		end,
		CreateFontString = function()
			return Region()
		end,
		CreateTexture = function()
			return Region()
		end,
	}
	return setmetatable({ points = {}, scripts = {} }, {
		__index = function(_, key)
			return methods[key] or function() end
		end,
	})
end

local color = { GetRGB = function() end }

-- The lines the game's tooltip was given, and the row's own tooltip: a vendor reagent, whose vendor is
-- nil until the catalogue's queue has read who sells it.
local lines = {}
local vendors = {}
local drawn = 0
local GameTooltip = {
	SetItemByID = function() end,
	SetOwner = function()
		lines = {}
	end,
	Show = function() end,
	AddLine = function(_, text)
		lines[#lines + 1] = text
	end,
}

local view, provider
local function CreateFrame(_, _, _, template)
	local frame = Region()
	if template == "WowScrollBoxList" then
		frame.SetDataProvider = function(_, list)
			provider = list
		end
	end
	return frame
end
local function CreateView()
	view = Region()
	function view:SetElementExtentCalculator(calculator)
		self.extent = calculator
	end
	function view:SetElementFactory(factory)
		self.factory = factory
	end
	return view
end

local ns = {}
local env = setmetatable({
	-- SafeCall hands a caught error to the game's handler: here it fails the spec.
	geterrorhandler = function()
		return function(message)
			io.stderr:write("error handler: ", tostring(message), "\n")
			os.exit(1)
		end
	end,
	GameTooltip = GameTooltip,
	CreateFrame = CreateFrame,
	CreateScrollBoxListLinearView = CreateView,
	CreateDataProvider = function(elements)
		return { elements = elements }
	end,
	ScrollUtil = { InitScrollBoxListWithScrollBar = function() end },
	ScrollBoxConstants = { RetainScrollPosition = true },
	HIGHLIGHT_FONT_COLOR = color,
	GRAY_FONT_COLOR = color,
}, { __index = _G })
setfenv(assert(loadfile("Core/SafeCall.lua")), env)("SkillUpForever", ns)
setfenv(assert(loadfile("Core/Changes.lua")), env)("SkillUpForever", ns)
setfenv(assert(loadfile("UI/List.lua")), env)("SkillUpForever", ns)

ns.NearestVendor = function(itemID)
	return vendors[itemID]
end
ns.AddNearest = function(tooltip, label, npcID)
	if npcID then
		tooltip:AddLine(label .. ": " .. npcID)
	end
end

local list = ns.CreateList(Region())
list:Add({
	text = "Linen Cloth",
	tooltip = function(tooltip)
		drawn = drawn + 1
		tooltip:SetItemByID(THREAD)
		tooltip:AddLine("Have (bags and bank): 0")
		ns.AddNearest(tooltip, "Nearest vendor", ns.NearestVendor(THREAD))
	end,
})
list:Finish()

-- The row frame the scroll box would draw for that element.
local initializer
view.factory(function(_, init)
	initializer = init
end, provider.elements[1])
local row = Region()
initializer(row, provider.elements[1])

-- First hover, with the vendor read still in flight.
row.scripts.OnEnter(row)
equal(drawn, 1, "a hover draws the row's tooltip")
equal(table.concat(lines, " | "), "Have (bags and bank): 0", "with no vendor line while the read is out")

-- The read finishes and the catalogue reports the sources changed. The game calls UpdateTooltip on its
-- own a few times a second; the row draws itself again there, without a second hover.
vendors[THREAD] = SELLER
ns.Changed("sources")
row:UpdateTooltip()
equal(drawn, 2, "and draws again once the sources have changed")
equal(table.concat(lines, " | "), "Have (bags and bank): 0 | Nearest vendor: " .. SELLER, "vendor line and all")
row:UpdateTooltip()
equal(drawn, 2, "once")

Client.report("tooltip_stale_spec")
