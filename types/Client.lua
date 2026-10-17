---@meta

-- FrameXML surfaces absent from Ketho's pinned Core annotations. Signatures follow
-- Gethe/wow-ui-source forever @ c6e89983189e4f626f549204a23c2d2bea93080a.
-- These declarations never load in the client.
---@type table<string, fun(msg: string)>
SlashCmdList = {}
---@type MessageFrame
DEFAULT_CHAT_FRAME = nil
-- Frames Escape closes, by name.
---@type string[]
UISpecialFrames = {}
---@type Frame
MerchantFrame = nil
---@type table<string, number>
SOUNDKIT = {}
---@type {Refresh: number}
MenuResponse = {}
---@type {ContinueOnAddOnLoaded: fun(name: string, callback: fun()), ContinueAfterAllEvents: fun(callback: function, ...: string)}
EventUtil = {}

---@class EditModeManagerFrame : Frame
---@field IsEditModeActive fun(self: EditModeManagerFrame): boolean
---@type EditModeManagerFrame?
EditModeManagerFrame = nil

-- GlobalStrings the client defines from its GlobalStrings DB2 in the player's language
-- (enUS values from wago.tools, Forever build 1.60.1.70009).
APPRENTICE = "Apprentice"
UNKNOWN = "Unknown"
JOURNEYMAN = "Journeyman"
EXPERT = "Expert"
ARTISAN = "Artisan"
DEFAULT = "Default"
OFF = "Off"
TOTAL = "Total"
UNIT_SKINNABLE_LEATHER = "Skinnable"
UNIT_SKINNABLE_HERB = "Requires Herbalism"
UNIT_SKINNABLE_ROCK = "Requires Mining"
ITEM_MIN_SKILL = "Requires %s (%d)"

---@class SkillUpProfessionFrame : Frame
---@field CraftingPage SkillUpCraftingPage
---@field BookPage Frame
---@field professionInfo? ProfessionInfo
---@field ProfessionsOverviewTab SkillUpSideTab
---@field rightProfessionTabs SkillUpSideTab[]
---@field SetPortraitToAsset fun(self: SkillUpProfessionFrame, asset: fileID|string)
---@field GetPortrait fun(self: SkillUpProfessionFrame): Texture
---@field RightTabSelected fun(self: SkillUpProfessionFrame, tab: SkillUpSideTab)
---@field RefreshRightTabs fun(self: SkillUpProfessionFrame)
---@type SkillUpProfessionFrame
ProfessionsFrame = nil

---@class SkillUpCraftingPage : Frame
---@field RecipeList SkillUpRecipeList
---@field SchematicForm SkillUpSchematicForm
---@field CreateAllButton? Button
---@field Init fun(self: SkillUpCraftingPage, info: ProfessionInfo)

---@class SkillUpSchematicForm : Frame
---@field GetRecipeInfo? fun(self: SkillUpSchematicForm): TradeSkillRecipeInfo?

-- Blizzard_AuctionHouseUI's frame; its public SetSearchText fills the search box and queries nothing.
---@class SkillUpAuctionHouseFrame : Frame
---@field SetSearchText fun(self: SkillUpAuctionHouseFrame, text: string): boolean
---@type SkillUpAuctionHouseFrame?
AuctionHouseFrame = nil

---@class SkillUpRecipeList : Frame
---@field ScrollBox SkillUpRecipeScrollBox
---@field FilterDropdown DropdownButton
---@field SelectRecipe fun(self: SkillUpRecipeList, info: TradeSkillRecipeInfo, scroll: boolean)

---@class SkillUpRecipeRow : Button
---@field Count FontString
---@field LockedIcon Texture
---@field SkillUps FontString
---@field Label FontString
---@field SkillUpText? FontString
---@field subText FontString

---@class SkillUpRecipeNodeData
---@field recipeInfo? TradeSkillRecipeInfo
---@field isDivider? boolean
---@field dividerHeight? number

---@class SkillUpTreeNode
---@field GetData fun(self: SkillUpTreeNode): SkillUpRecipeNodeData
---@field GetNodes fun(self: SkillUpTreeNode): SkillUpTreeNode[]

---@class SkillUpTreeProvider
---@field GetRootNode fun(self: SkillUpTreeProvider): SkillUpTreeNode
---@field Insert fun(self: SkillUpTreeProvider, data: SkillUpRecipeNodeData)

---@return SkillUpTreeProvider
function CreateTreeDataProvider() end

---@class SkillUpScrollBox : Frame
---@field ScrollToBegin fun(self: SkillUpScrollBox)
---@field SetDataProvider fun(self: SkillUpScrollBox, provider: SkillUpDataProvider, retain?: boolean)

---@class SkillUpRecipeScrollBox : SkillUpScrollBox, CallbackRegistryMixin
---@field GetDataProvider fun(self: SkillUpRecipeScrollBox): SkillUpTreeProvider?
---@field SetDataProvider fun(self: SkillUpRecipeScrollBox, provider: SkillUpTreeProvider, retain?: boolean)

---@class SkillUpScrollBar : Frame
---@field SetHideIfUnscrollable fun(self: SkillUpScrollBar, hide: boolean)

---@class SkillUpDataProvider
---@field GetSize fun(self: SkillUpDataProvider): integer

---@param tbl? table
---@return SkillUpDataProvider
function CreateDataProvider(tbl) end

---@alias SkillUpElementInitializer fun(frame: Frame, elementData: SkillUpListElement)
---@alias SkillUpElementFactory fun(factory: fun(template: string, initializer: SkillUpElementInitializer), elementData: SkillUpListElement)

---@class SkillUpScrollView
---@field SetElementExtent fun(self: SkillUpScrollView, extent: number)
---@field SetElementExtentCalculator fun(self: SkillUpScrollView, calculator: fun(dataIndex: integer, elementData: SkillUpListElement): number)
---@field SetElementFactory fun(self: SkillUpScrollView, elementFactory: SkillUpElementFactory)
---@return SkillUpScrollView
function CreateScrollBoxListLinearView() end

---@type {UpdateImmediately: boolean, RetainScrollPosition: boolean}
ScrollBoxConstants = {}
ScrollUtil = {}
---@param box SkillUpScrollBox
---@param bar SkillUpScrollBar
---@param view SkillUpScrollView
function ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view) end
---@param box SkillUpRecipeScrollBox
---@param callback fun(owner: SkillUpNamespace, row: SkillUpRecipeRow, node: SkillUpTreeNode)
---@param owner SkillUpNamespace
function ScrollUtil.AddInitializedFrameCallback(box, callback, owner) end

Professions = {}
---@return SkillUpProfessionInfo?
function Professions.GetProfessionInfo() end
---@param info TradeSkillRecipeInfo
---@return TradeSkillRecipeInfo?
function Professions.GetHighestLearnedRecipe(info) end

-- The character's own skill lines, from Forever's Skills pane (SkillInfoDocumentation.lua).
---@class SkillUpSkillLine
---@field skillID integer
---@field name string
---@field isHeader boolean
---@field rank number
---@field modifier number
---@field parentSkillLineID integer
---@field skillLineCategoryID integer

C_SkillInfo = {}
---@return integer
function C_SkillInfo.GetNumSkillLines() end
---@param index integer
---@return SkillUpSkillLine?
function C_SkillInfo.GetSkillLineInfo(index) end
---@param ID integer
---@return SkillUpSkillLine?
function C_SkillInfo.GetSkillLineInfoByID(ID) end

---@class SkillUpSideTab : Frame
---@field Icon Texture
---@field tooltipText string
---@field SetFillToInterior fun(self: SkillUpSideTab, fill: boolean)
---@field SetChecked fun(self: SkillUpSideTab, checked: boolean)
---@field SetCustomOnMouseUpHandler fun(self: SkillUpSideTab, callback: fun(tab: SkillUpSideTab, button: string, upInside: boolean))

---@class DropdownButton : Button
---@field SetupMenu fun(self: DropdownButton, generator: fun(owner: DropdownButton, root: RootMenuDescriptionProxy))
---@field GenerateMenu fun(self: DropdownButton)

-- Ketho declares the native tooltip widget; Forever also mixes in GameTooltipDataMixin.
---@class GameTooltip
---@field RefreshData fun(self: GameTooltip)
---@return string? name
---@return string? link
---@return integer? itemID
function GameTooltip:GetItem() end

---@param tooltip GameTooltip
---@param title string
function GameTooltip_SetTitle(tooltip, title) end
---@param tooltip GameTooltip
function GameTooltip_AddBlankLineToTooltip(tooltip) end
---@param tooltip GameTooltip
---@param text string
---@param color ColorMixin
function GameTooltip_AddColoredLine(tooltip, text, color) end
---@param tooltip GameTooltip
---@param left string
---@param right string
---@param leftColor ColorMixin
---@param rightColor ColorMixin
function GameTooltip_AddColoredDoubleLine(tooltip, left, right, leftColor, rightColor) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddNormalLine(tooltip, text) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddDisabledLine(tooltip, text) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddHighlightLine(tooltip, text) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddInstructionLine(tooltip, text) end
---@param tooltip GameTooltip
---@param frame Frame
---@param padding? number
function GameTooltip_InsertFrame(tooltip, frame, padding) end
function GameTooltip_Hide() end

---@param link string
---@return boolean
function ChatEdit_InsertLink(link) end
---@param link string
---@return boolean
function HandleModifiedItemClick(link) end

TooltipDataProcessor = {}
---@param kind Enum.TooltipDataType
---@param callback fun(tooltip: GameTooltip, data: TooltipData)
function TooltipDataProcessor.AddTooltipPostCall(kind, callback) end

UiMapPoint = {}
---@param mapID integer
---@param x number
---@param y number
---@return UiMapPoint
function UiMapPoint.CreateFromCoordinates(mapID, x, y) end

---@class SkillUpTrainerElement
---@field skillIndex? integer
---@field data? SkillUpTrainerElement

---@class SkillUpTrainerButton : Button
---@field SkillUpText? FontString
---@field subText FontString
---@field GetElementData fun(self: SkillUpTrainerButton): SkillUpTrainerElement

---@class SkillUpTrainerScrollBox : Frame
---@field ForEachFrame fun(self: SkillUpTrainerScrollBox, callback: fun(button: SkillUpTrainerButton))

---@class SkillUpTrainerFrame : Frame
---@field ScrollBox SkillUpTrainerScrollBox
---@field skillStepButton SkillUpTrainerButton
---@type SkillUpTrainerFrame
ClassTrainerFrame = nil
---@type {GetTrainerType: fun(): number}
C_Trainer = {}

---@class SkillUpTrackerStep
---@field text string
---@field book string|false|nil A rank's book, by name: got at a vendor, not a trainer.
---@field quest string|false|nil A rank's quest, by name: got from its giver, not a trainer.
---@field nearest fun(byTravel: boolean?): integer?, string The NPC to go to, and its tooltip label.

---@class SkillUpTrackerBlock : Frame
---@field id integer
---@field profession string
---@field plan SkillUpPlan
---@field items SkillUpNeededItem[]
---@field steps SkillUpTrackerStep[]
---@field vendorMissing {name: string, itemID: integer, vendor: integer}[]
---@field SetHeader fun(self: SkillUpTrackerBlock, text: string)
---@field AddObjective fun(self: SkillUpTrackerBlock, id: string|number, text: string, template?: string, useFullHeight?: boolean, dashStyle?: number, colorStyle?: SkillUpObjectiveColor): Frame

---@class SkillUpTrackerModule : Frame
---@field uiOrder number
---@field MarkDirty fun(self: SkillUpTrackerModule)
---@field SetHeader fun(self: SkillUpTrackerModule, text: string)
---@field GetContextMenuParent fun(self: SkillUpTrackerModule): Frame
---@field GetBlock fun(self: SkillUpTrackerModule, id: integer): SkillUpTrackerBlock
---@field LayoutBlock fun(self: SkillUpTrackerModule, block: SkillUpTrackerBlock): boolean
---@type ForeverNativeTrackerFrame
ObjectiveTrackerFrame = nil

---@class ForeverTrackerHostAPI
---@field GetSettings fun(): ForeverTrackerSettings
---@field GetScale fun(): number
---@field SetScale fun(scale: number)
---@field IsAttachedToQuestTracker fun(): boolean
---@field SetAttached fun(attached: boolean)
---@field OnAttachmentChanged fun(callback: fun(attached: boolean))
---@field SavePosition fun(x: number, y: number)
---@field Attach fun(module: Frame)
---@field IsAttached fun(module: Frame?): boolean
---@type ForeverTrackerHostAPI?
ForeverTrackerHost = nil
---@class SkillUpObjectiveColor : ColorRGBData
---@field reverse? SkillUpObjectiveColor
---@type {Complete: SkillUpObjectiveColor}
OBJECTIVE_TRACKER_COLOR = {}
---@type number
OBJECTIVE_DASH_STYLE_HIDE = nil

---@alias SkillUpSettingValue boolean|string|number
---@class SkillUpSetting
---@field SetValueChangedCallback fun(self: SkillUpSetting, callback: fun())
---@class SkillUpCategory
---@field GetID fun(self: SkillUpCategory): number
---@class SkillUpSettingOptions
---@field Add fun(self: SkillUpSettingOptions, value: SkillUpSettingValue, text: string)
---@field GetData fun(self: SkillUpSettingOptions): {value: SkillUpSettingValue, text: string}[]
Settings = {}
Settings.VarType = { Boolean = "boolean", String = "string", Number = "number" }
---@param name string
---@return SkillUpCategory
function Settings.RegisterVerticalLayoutCategory(name) end
---@param parent SkillUpCategory
---@param name string
---@return SkillUpCategory
function Settings.RegisterVerticalLayoutSubcategory(parent, name) end
---@param parent SkillUpCategory
---@param frame Frame
---@param name string
---@return SkillUpCategory
function Settings.RegisterCanvasLayoutSubcategory(parent, frame, name) end
---@param category SkillUpCategory
---@param variable string
---@param key string
---@param db SkillUpDB
---@param varType string
---@param name string
---@param default SkillUpSettingValue
---@return SkillUpSetting
function Settings.RegisterAddOnSetting(category, variable, key, db, varType, name, default) end
---@param category SkillUpCategory
---@param variable string
---@param varType string
---@param name string
---@param default number|boolean
---@param getValue fun(): number|boolean
---@param setValue fun(value: number|boolean)
---@return SkillUpSetting
function Settings.RegisterProxySetting(category, variable, varType, name, default, getValue, setValue) end
---@param variable string
function Settings.NotifyUpdate(variable) end
---@class SkillUpSliderOptions
---@field SetLabelFormatter fun(self: SkillUpSliderOptions, labelType: number, formatter: fun(value: number): string)
---@param minValue number
---@param maxValue number
---@param step number
---@return SkillUpSliderOptions
function Settings.CreateSliderOptions(minValue, maxValue, step) end
---@param setting SkillUpSetting
---@param options SkillUpSliderOptions
---@param tooltip string
---@return SkillUpSettingInitializer
function Settings.CreateSliderInitializer(setting, options, tooltip) end
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
---@class SkillUpSettingInitializer
---@param setting SkillUpSetting
---@param options nil
---@param tooltip string
---@return SkillUpSettingInitializer
function Settings.CreateCheckboxInitializer(setting, options, tooltip) end
---@param setting SkillUpSetting
---@param options fun(): {value: SkillUpSettingValue, text: string}[]
---@param tooltip string
---@return SkillUpSettingInitializer
function Settings.CreateDropdownInitializer(setting, options, tooltip) end
---@param category SkillUpCategory
---@param initializer SkillUpSettingInitializer
function Settings.RegisterInitializer(category, initializer) end
---@return SkillUpSettingOptions
function Settings.CreateControlTextContainer() end
---@param category SkillUpCategory
function Settings.RegisterAddOnCategory(category) end
---@param variable string
---@param value SkillUpSettingValue
function Settings.SetValue(variable, value) end
---@param categoryID number
function Settings.OpenToCategory(categoryID) end
---@param name string
---@param buttonText string
---@param onClick fun()
---@param tooltip string?
---@param addSearchTags boolean?
---@return SkillUpSettingInitializer
function CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags) end

-- Professions decorates native recipe/profession records before dispatching callbacks.
---@class SkillUpProfessionInfo : ProfessionInfo
---@field displayName string

---@class TradeSkillRecipeInfo
---@field favoritesInstance? boolean

-- TooltipData's ID is supplied for item/spell tooltips in Forever, but is absent
-- from Ketho's hand-written TooltipData structure at the pinned revision.
---@class TooltipData
---@field id? integer

-- Ketho's legacy native declaration has no returns; Forever's trainer supplies
-- these together, and supplies no rank when the trainer has no profession.
---@return number? rank
---@return number? maxRank
---@return number? modifier
function GetTrainerTradeskillRankValues() end

---@class ForeverTrackerSettings
---@field attached boolean
---@field scale? number tracker size, 1 is the stock size
---@field x? number
---@field y? number

---@class ForeverTrackerNamespace
---@field TrackerHost? ForeverTrackerHostAPI
---@field TrackerQuestie? ForeverTrackerQuestie Questie's quest list, from UI/TrackerQuestie.lua
---@field TrackerHostSettings? fun(): ForeverTrackerSettings
---@field L table<string, string>
