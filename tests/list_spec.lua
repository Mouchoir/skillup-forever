-- Run from the repository root: luajit tests/list_spec.lua
-- The addon's list: the elements a caller adds, the height the game lays each one out at, and the frames
-- the game draws them with, a full-size item icon in its stock border, the name beside it and the
-- supporting facts on the line under it, all built from the element the scroll box hands the initializer.
local Client = dofile("tests/client.lua")
local equal = Client.equal

-- A frame or region that records its anchors, text, colour, visibility and size; anything else is accepted
-- and ignored. A font string reports a wrapped height for a long line, so the message height can be read.
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
		SetTextColor = function(self, r, g, b)
			self.color = { r, g, b }
		end,
		SetShown = function(self, shown)
			self.shown = shown
		end,
		Show = function(self)
			self.shown = true
		end,
		Hide = function(self)
			self.shown = false
		end,
		SetSize = function(self, width, height)
			self.width, self.height = width, height
		end,
		SetWidth = function(self, width)
			self.width = width
		end,
		SetHeight = function(self, height)
			self.height = height
		end,
		SetWordWrap = function(self, wrap)
			self.wordWrap = wrap
		end,
		SetScript = function(self, name, script)
			self.scripts[name] = script
		end,
		GetWidth = function()
			return 300
		end,
		GetStringHeight = function(self)
			return self.text and #self.text > 20 and 24 or 12
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

local view, scrollBox, provider, retained

local function CreateFrame(_, _, _, template)
	local frame = Region()
	if template == "WowScrollBoxList" then
		scrollBox = frame
		frame.SetDataProvider = function(_, list, retain)
			provider, retained = list, retain
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

local color = { GetRGB = function() end }
local ns = { WhenEvent = function() end, WhenStale = function() end }
local env = setmetatable({
	GameTooltip = Region(),
	CreateFrame = CreateFrame,
	CreateScrollBoxListLinearView = CreateView,
	CreateDataProvider = function(elements)
		return { elements = elements }
	end,
	ScrollUtil = { InitScrollBoxListWithScrollBar = function() end },
	ScrollBoxConstants = { RetainScrollPosition = true },
	HIGHLIGHT_FONT_COLOR = color,
	GRAY_FONT_COLOR = color,
	NORMAL_FONT_COLOR = color,
}, { __index = _G })
setfenv(assert(loadfile("UI/List.lua")), env)("SkillUpForever", ns)

local list = ns.CreateList(Region())

-- The anchors a region was last given at `point`: its arguments after the point's name.
local function Anchor(region, point)
	local found
	for _, anchor in ipairs(region.points) do
		if anchor[1] == point then
			found = anchor
		end
	end
	return found or {}
end

-- The list is the game's own scroll box, inset to leave room for the scroll bar.
equal(Anchor(scrollBox, "TOPLEFT")[2], 4, "the scroll box is inset 4 from the left")
equal(Anchor(scrollBox, "BOTTOMRIGHT")[2], -18, "and leaves room for the scroll bar")

-- Fills the list with one of each kind: a row with facts, a row without, a heading and two messages, one
-- short and one long enough to wrap to a second line.
local function Fill()
	list:Begin()
	list:Add({ icon = 134400, text = "Heavy Linen Bandage", detail = "18 crafts to 90, 54s" })
	list:Add({ text = "Total 54s" })
	list:Heading("Head")
	list:Message("Nothing to buy.")
	list:Message("A message long enough to wrap onto a second line in the list.")
	list:Finish()
end
Fill()

-- The elements are what the caller added, in order, and the scroll box was handed them to draw itself.
equal(#list.rows, 5, "the last render holds every element")
equal(list.rows[1].kind, "row", "a row is its own kind")
equal(list.rows[1].entry.text, "Heavy Linen Bandage", "with the entry the caller added")
equal(list.rows[2].kind, "row", "a second row is a row too")
equal(list.rows[3].kind, "heading", "a heading is its own kind")
equal(list.rows[3].text, "Head", "with its text")
equal(list.rows[4].kind, "message", "a message is its own kind")
equal(list.rows[4].text, "Nothing to buy.", "with its text")
equal(provider.elements, list.rows, "the scroll box draws the last render's elements")
equal(retained, true, "keeping the scroll position between renders")

-- Each kind is laid out at its own height; a message is as tall as its wrapped text, with a floor.
equal(view.extent(1, list.rows[1]), 46, "a row is the game's item height")
equal(view.extent(3, list.rows[3]), 26, "a heading is its stock line's height")
equal(view.extent(4, list.rows[4]), 20, "a one-line message keeps the minimum height")
equal(view.extent(5, list.rows[5]), 32, "a wrapped message is as tall as its lines")

-- The factory picks a template a kind, so the scroll box's pools stay apart.
local function Materialize(elementData, frame)
	local template, initializer
	view.factory(function(name, init)
		template, initializer = name, init
	end, elementData)
	frame = frame or Region()
	initializer(frame, elementData)
	return frame, template
end

-- A row is the game's item: a 37px icon in the stock border, the name beside it, the facts under it.
local row, rowTemplate = Materialize(list.rows[1])
equal(rowTemplate, "SkillUpForeverListRowTemplate", "a row is built from the row template")
equal(row.kind, "row", "and knows it is a row")
equal(Anchor(row.Icon, "LEFT")[2], 6, "the icon sits 6 in from the left")
equal(row.Icon.width, 37, "at the game's own item size")
equal(row.Icon.shown, true, "and is shown when the entry has one")
equal(row.IconBorder.shown, true, "with the stock item border over it")
equal(Anchor(row.IconBorder, "LEFT")[2], row.Icon, "the border sits on the icon")
equal(row.Text.text, "Heavy Linen Bandage", "the name is beside the icon")
equal(Anchor(row.Text, "TOPLEFT")[2], row.Icon, "anchored to the icon")
equal(Anchor(row.Text, "TOPLEFT")[3], "TOPRIGHT", "at its right")
equal(Anchor(row.Text, "RIGHT")[2], row, "and stops at the row's right")
equal(row.Detail.text, "18 crafts to 90, 54s", "the facts are on the line under the name")
equal(Anchor(row.Detail, "TOPLEFT")[2], row.Text, "under the name")
equal(Anchor(row.Detail, "TOPLEFT")[3], "BOTTOMLEFT", "at its bottom left")

-- The same pooled frame redrawn for a later element drops what the new element does not have.
local pooled = Region()
Materialize(list.rows[1], pooled)
local detail = pooled.Detail
row, rowTemplate = Materialize(list.rows[2], pooled)
equal(rowTemplate, "SkillUpForeverListRowTemplate", "the second row is built from the same template")
equal(row.kind, "row", "the redrawn frame is still a row")
equal(pooled.Detail, detail, "the scroll box's frame is reused")
equal(pooled.Detail.shown, false, "a row without facts shows no detail")

-- A heading is a stock line and a message is wrapped, measured text.
local heading, headingTemplate = Materialize(list.rows[3])
equal(headingTemplate, "SkillUpForeverListHeadingTemplate", "a heading is built from the heading template")
equal(heading.kind, "heading", "and knows it is a heading")
equal(heading.Text.text, "Head", "with its text")
local message, messageTemplate = Materialize(list.rows[5])
equal(messageTemplate, "SkillUpForeverListMessageTemplate", "a message is built from the message template")
equal(message.kind, "message", "and knows it is a message")
equal(message.Text.text, list.rows[5].text, "with its text")
equal(message.Text.wordWrap, true, "wrapped")

-- A left click is the row's own and a right-click opens its menu, from the row; a row with only a menu still
-- takes the mouse.
local menus, clicks = {}, {}
env.GameTooltip_Hide = function() end
env.MenuUtil = {
	CreateContextMenu = function(owner, generator)
		menus[#menus + 1] = { owner = owner, generator = generator }
	end,
}
local function Menu() end
list:Begin()
list:Add({
	text = "Linen Bandage",
	click = function(clicked)
		clicks[#clicks + 1] = clicked
	end,
	menu = Menu,
})
list:Add({ text = "Skipped (1)", menu = Menu })
list:Add({ text = "Total 54s" })
list:Finish()
local clickable = Materialize(list.rows[1])
local mouse
clickable.EnableMouse = function(_, enabled)
	mouse = enabled
end
Materialize(list.rows[1], clickable)
clickable.scripts.OnClick(clickable, "LeftButton")
equal(clicks[1], clickable, "a left click is the row's own, given the row")
equal(#menus, 0, "and opens no menu")
clickable.scripts.OnClick(clickable, "RightButton")
equal(#clicks, 1, "a right-click is not a left click")
equal(menus[1].owner, clickable, "it opens the menu on the row")
equal(menus[1].generator, Menu, "filled by the entry's menu")
Materialize(list.rows[2], clickable)
equal(mouse, true, "a row with only a menu takes the mouse")
Materialize(list.rows[3], clickable)
equal(mouse, false, "a row with nothing to do does not")

Client.report("list_spec")
