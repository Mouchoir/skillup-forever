-- Run from the repository root: luajit tests/art_spec.lua
-- Art.lua on its own, with a stub C_Texture.GetAtlasInfo and a stub texture: an atlas fits its box at its own
-- aspect, and its markup takes its width from that aspect.
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual, expected, label)
	equal(math.abs(actual - expected) < 1e-6, true, ("%s (%s ~ %s)"):format(label, actual, expected))
end

local ATLASES = {
	wide = { width = 209, height = 46 },
	tall = { width = 10, height = 14 },
}
local C_Texture = {
	GetAtlasInfo = function(name)
		return ATLASES[name]
	end,
}

local Texture = {}
Texture.__index = Texture
function Texture:SetAtlas(atlas)
	self.atlas = atlas
end
function Texture:SetSize(width, height)
	self.width, self.height = width, height
end
function Texture:SetTexture(file)
	self.file = file
end
function Texture:SetTexCoord(...)
	self.coords = { ... }
end

local ns = {}
local chunk = assert(loadfile("UI/Art.lua"))
setfenv(chunk, setmetatable({ C_Texture = C_Texture }, { __index = _G }))
chunk("SkillUpForever", ns)
local Art = ns.Art

-- Fit: the largest size in the box at the atlas's aspect.
do
	local texture = setmetatable({}, Texture)
	local width, height = Art.Fit(texture, "tall", 20, 20)
	equal(texture.atlas, "tall", "fit: the atlas")
	near(height, 20, "fit: a tall atlas fills the box's height")
	near(width / height, 10 / 14, "fit: a tall atlas at its own aspect")
	equal(texture.width, width, "fit: sized")
	width, height = Art.Fit(texture, "wide", 22, 25)
	near(width, 22, "fit: a wide atlas fills the box's width")
	near(width / height, 209 / 46, "fit: a wide atlas at its own aspect")
	width, height = Art.Fit(texture, "unknown", 14, 18)
	equal(width, 14, "fit: an unknown atlas is square")
	equal(height, 14, "fit: an unknown atlas is square, inside the box")
end

-- Icon: a square file icon, whole, with an atlas's earlier crop reset.
do
	local texture = setmetatable({ coords = { 0.1, 0.9, 0.1, 0.9 } }, Texture)
	Art.Icon(texture, "Interface\\Icon", 62)
	equal(texture.file, "Interface\\Icon", "icon: the file")
	equal(table.concat(texture.coords, " "), "0 1 0 1", "icon: whole")
	equal(texture.width, 62, "icon: as wide")
	equal(texture.height, 62, "icon: as tall")
end

-- Markup: the height given, the width from the aspect.
do
	equal(Art.Markup("tall", 14), "|A:tall:14:10|a", "markup: the width from the aspect")
	equal(Art.Markup("unknown", 14), "|A:unknown:14:14|a", "markup: an unknown atlas is square")
end

print(("art_spec: %d checks passed"):format(checks))
