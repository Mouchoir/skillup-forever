std = "lua51"
max_line_length = 120
exclude_files = { "tools/.cache/**", ".release/**", ".types/**", "types/**", ".claude/**" }
ignore = { "212/_.*" } -- unused args prefixed with _

globals = { "ForeverFamily", "ForeverTrackerHost",
	"SkillUpForeverDB",
	"SkillUpForever",
	"SkillUpForever_OnAddonCompartmentClick",
	"SLASH_SKILLUPFOREVER1",
	"SLASH_SKILLUPFOREVER2",
	"SlashCmdList",
}

read_globals = { "CreateFramePoolCollection", "C_XMLUtil",
	"C_TradeSkillUI", "CreateColor", "CreateFrame", "CreateTreeDataProvider", "ScrollBoxConstants", "strcmputf8i", "DEFAULT_CHAT_FRAME", "Enum", "EventRegistry", "EventUtil",
	"GameTooltip", "GameTooltip_AddColoredLine", "GameTooltip_AddDisabledLine", "GameTooltip_InsertFrame",
	"GameTooltip_SetTitle", "hooksecurefunc", "Professions", "ProfessionsFrame", "ScrollUtil",
	"Settings", "strtrim", "UIParent",
	"Auctionator", "C_CurrencyInfo", "C_Item", "C_MerchantFrame",
	"GameTooltip_AddBlankLineToTooltip", "GetBuildInfo", "GetMerchantItemID", "GetMerchantNumItems", "GetNormalizedRealmName", "time",
	"UnitFactionGroup", "Menu", "MenuResponse", "C_Timer",
	"DIFFICULT_DIFFICULTY_COLOR", "EASY_DIFFICULTY_COLOR", "FAIR_DIFFICULTY_COLOR", "GRAY_FONT_COLOR",
	"HIGHLIGHT_FONT_COLOR", "RED_FONT_COLOR", "TRIVIAL_DIFFICULTY_COLOR",
	"C_SkillInfo", "C_PaperDollInfo", "C_Spell", "C_Texture", "C_Trainer", "C_TooltipInfo", "ClassTrainerFrame", "ContinuableContainer", "GameTooltip_AddNormalLine",
	"GameTooltip_Hide", "GetMoney", "GetNumTrainerServices", "GetProfessionInfo", "GetProfessions",
	"GetTrainerServiceCost", "GetTrainerServiceInfo", "GetTrainerServiceSkillReq", "GetTrainerServiceStepIndex", "UnitLevel", "UnitClass", "PlaySound", "SOUNDKIT", "GameTooltip_AddColoredDoubleLine",
	"GameTooltip_AddHighlightLine", "GameTooltip_AddInstructionLine", "IsModifiedClick", "ChatEdit_InsertLink",
	"HandleModifiedItemClick", "IsShiftKeyDown", "CreateScrollBoxListLinearView", "CreateDataProvider", "CreateSettingsButtonInitializer",
	"GetTrainerTradeskillRankValues", "C_SpellBook", "issecretvalue", "Item", "NORMAL_FONT_COLOR",
	"TooltipDataProcessor", "UnitName", "UnitGUID", "BuyMerchantItem", "GetMerchantItemMaxStack", "MerchantFrame", "MenuUtil", "Mixin", "ObjectiveTrackerFrame", "OBJECTIVE_TRACKER_COLOR", "OBJECTIVE_DASH_STYLE_HIDE",
	"C_Map", "C_SuperTrack", "CreateVector2D", "TomTom", "UiMapPoint", "UnitPosition", "Syndicator", "tContains",
	"ShortestPathForever", "InCombatLockdown", "GetLocale", "C_AddOns",
	"LibQuestieDB", "Questie", "AtlasLoot", "bit", "debugprofilestop", "loadstring", "setfenv",
	"UNKNOWN", "UNIT_SKINNABLE_LEATHER", "UNIT_SKINNABLE_HERB", "UNIT_SKINNABLE_ROCK", "UnitRace", "geterrorhandler", "debugstack", "ChatFontNormal", "UISpecialFrames", "APPRENTICE", "JOURNEYMAN", "EXPERT", "ARTISAN", "DEFAULT", "OFF", "TOTAL",
}

files["Data/Thresholds.lua"] = { max_line_length = false }
files["Data/Sources.lua"] = { max_line_length = false }
files["Locales/"] = { max_line_length = false } -- one phrase per line, however long
files["tests/"] = { std = "+luajit" }
read_globals[#read_globals + 1] = "EditModeManagerFrame"
read_globals[#read_globals + 1] = "AuctionHouseFrame"

read_globals[#read_globals + 1] = "MinimalSliderWithSteppersMixin"
