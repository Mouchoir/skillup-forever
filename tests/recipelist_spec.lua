-- A native provider replacement must sort through its callback without replacing native methods.
local function noop() end
local provider, callback, owner, replacements = nil, nil, nil, 0
local box = {}
function box.RegisterCallback(_, event, fn, target)
	assert(event == "OnDataProviderReassigned")
	callback, owner = fn, target
end
function box.GetDataProvider()
	return provider
end
function box.SetDataProvider(_, value)
	provider, replacements = value, replacements + 1
	assert(replacements < 10, "sorting must not recurse through provider callbacks")
	callback(owner)
end
local original = box.SetDataProvider
local function tree()
	local nodes = {}
	return {
		Insert = function(_, data)
			nodes[#nodes + 1] = {
				GetData = function()
					return data
				end,
				GetNodes = function()
					return {}
				end,
			}
		end,
		GetRootNode = function()
			return {
				GetNodes = function()
					return nodes
				end,
			}
		end,
	}
end
local ns = {
	L = {},
	db = { sortMode = "skill" },
	Model = {
		Get = function(id)
			return { id }
		end,
	},
	SkillContext = noop,
	AttachRoute = noop,
	AttachGear = noop,
	AttachAuctionSearch = noop,
	WhenStale = noop,
	ShowRecipeTooltip = noop,
	Print = function(msg)
		error(msg)
	end,
	SetSortMode = function()
		error("unexpected sort failure")
	end,
}
local env = setmetatable({
	ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = box } } },
	ScrollUtil = { AddInitializedFrameCallback = noop },
	EventRegistry = { RegisterCallback = noop },
	Menu = { ModifyMenu = noop },
	ScrollBoxConstants = { RetainScrollPosition = true },
	CreateTreeDataProvider = tree,
	hooksecurefunc = function()
		error("native recipe methods must stay unhooked")
	end,
}, { __index = _G })
setfenv(assert(loadfile("UI/RecipeList.lua")), env)("SkillUpForever", ns)
ns.AttachRecipeList()
local input = tree()
input:Insert({ recipeInfo = { recipeID = 30, learned = true } })
input:Insert({ recipeInfo = { recipeID = 10, learned = true } })
box:SetDataProvider(input)
assert(replacements == 2, "one native update and one sorted replacement")
assert(provider:GetRootNode():GetNodes()[1]:GetData().recipeInfo.recipeID == 10)
assert(box.SetDataProvider == original, "native method remains untouched")
ns.db.sortMode = "blizzard"
box:SetDataProvider(input)
assert(provider == input, "default sort leaves the native provider alone")
print("recipelist_spec: provider replacement, sort, recursion and native method identity passed")
