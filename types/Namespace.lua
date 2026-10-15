---@meta

-- The client passes this same table to each TOC file; no runtime import is available.
---@class SkillUpNamespace
---@field Art SkillUpArt
---@field TrackerHost? ForeverTrackerHostAPI
---@field TrackerHostSettings fun(): ForeverTrackerSettings
---@field Print fun(msg: string)
---@field Changed fun(kind: SkillUpChange)
---@field WhenStale fun(name: SkillUpStale, handler: fun())
---@field WhenEvent fun(event: WowEvent, watcher: fun(): SkillUpChange?)
---@field ProfessionSkillLine fun(name?: string, reported?: integer): integer?
---@field CharacterKey fun(): string
---@field ClientBuild fun(): string?
---@field NoteBuild fun()
---@field SellerFresh fun(seller: SkillUpSeller): boolean
---@field CollectMode fun(): SkillUpCollectMode
---@field SetCollectMode fun(mode: SkillUpCollectMode)
---@field ShowAllGear fun(): boolean
---@field SetShowAllGear fun(show: boolean)
---@field IsSkipped fun(recipeID: integer): boolean
---@field SetSkipped fun(recipeID: integer, skip: boolean)
---@field SkippedRecipes fun(skillLine: integer?): {recipeID: integer, name: string}[]
---@field AddSkippedMenu fun(description: RootMenuDescriptionProxy|ElementMenuDescriptionProxy, skillLine: integer)
---@field SkillContext fun(): SkillUpContext?
---@field PlayerProfessions fun(): table<integer, SkillUpProfession>
---@field IsLearned fun(recipeID: integer): boolean
---@field Describe fun(recipeInfo: TradeSkillRecipeInfo|SkillUpRecipeInfo, ctx?: SkillUpContext): SkillUpDescription
---@field FormatRow fun(d: SkillUpDescription): string
---@field RowColor fun(d: SkillUpDescription): ColorMixin
---@field Price fun(itemID: integer): SkillUpPrice?
---@field PriceSource fun(itemID: integer): SkillUpPriceSource?
---@field Reagents fun(recipeID: integer): SkillUpReagent[]?
---@field UsedIn fun(itemID: integer): integer[]
---@field CraftCost fun(recipeID: integer): number?, SkillUpValue?, number?
---@field NetCost fun(recipeID: integer): number?
---@field InitPrices fun()
---@field AttachRecipeList fun()
---@field RouteProfessions fun(): table<integer, SkillUpProfession>
---@field CraftedGear fun(level: number, classID: integer): SkillUpGearSlot[]
---@field Gear SkillUpGear
---@field TrainingFor fun(profession: SkillUpContext, recipeID: integer): number[]?
---@field TrainerChecks fun(): SkillUpTrainerCheck[]
---@field TrainerReport fun(): string[]
---@field RankName fun(cap: number): string?
---@field RecipeBands fun(profession: SkillUpContext, recipeID: integer): SkillUpBand[]
---@field LearnSkill fun(profession: SkillUpContext, recipeID: integer): number
---@field RecipeNPC fun(profession: SkillUpContext, recipeID: integer): integer?
---@field BestTraining fun(profession: SkillUpContext, known: table<integer, boolean>, offers: {recipeID: integer, fee: number}[]): integer?
---@field RouteBlocked fun(plan: SkillUpPlan): string?
---@field UnpricedReagents fun(plan: SkillUpPlan): integer[]
---@field PlanRoute fun(profession: SkillUpProfession): SkillUpPlan
---@field RankText fun(rank: SkillUpRank): string
---@field RankBookName fun(rank: SkillUpRank): string
---@field CreateList fun(parent: Frame): SkillUpList
---@field NextCraft fun(plan: SkillUpPlan): SkillUpCraft
---@field OpenSkillLine fun(): integer?
---@field ShowRecipe fun(recipeID: integer)
---@field AttachRoute fun()
---@field AttachGear fun()
---@field RouteTab? SkillUpSideTab
---@field GearTab? SkillUpSideTab
---@field HideRoute fun()
---@field HideGear fun()
---@field PlaceGearTab? fun()
---@field RegisterSettings fun()
---@field SetSortMode fun(mode: string)
---@field OpenSettings fun()
---@field HasAuctionator fun(): boolean
---@field AuctionatorAutoscan fun(): boolean?
---@field AuctionListName fun(profession: string): string
---@field Have fun(itemID: integer): number
---@field Readable fun(value: any): any
---@field AltCounts fun(itemID: integer): {name: string, count: number}[]
---@field RouteReagents fun(plan: SkillUpPlan): SkillUpNeededItem[]
---@field InitLive fun()
---@field LiveRecipes table<integer, SkillUpLiveRecipe>
---@field NoteLearnedRecipe fun(recipeID: integer, learned: boolean?): boolean
---@field RecipeSkillUps fun(recipeID: integer): integer
---@field RecipeRequirements fun(recipeID: integer): CraftingRecipeRequirement[]
---@field MissingTool fun(recipeID: integer): CraftingRecipeRequirement?
---@field RecipeStation fun(recipeID: integer): string?
---@field ToolItemID fun(name: string): integer?
---@field MissingToolItems fun(plan: SkillUpPlan): integer[]
---@field SubCraft fun(itemID: integer): {recipeID: integer, quantity: number}?
---@field IsTracked fun(skillLine?: integer): boolean
---@field TrackedNeeds fun(): SkillUpTracked[]
---@field TrackerAttached fun(): boolean
---@field SetTracked fun(skillLine: integer, tracked: boolean)
---@field AutoTrack fun(skillLine?: integer): boolean
---@field InitShopping fun()
---@field NPCLocation fun(npcID: integer): SkillUpLocation
---@field LocationText fun(where: SkillUpLocation): string
---@field SeeVendor fun(itemIDs: integer[]): boolean
---@field NearestNPC fun(npcIDs: integer[], byTravel?: boolean): integer?
---@field SetWaypoint fun(npcID: integer): boolean
---@field SuggestionNPC fun(suggestion: SkillUpSuggestionNPC): integer?
---@field RecipeSuggestions fun(profession: SkillUpContext, base: number): SkillUpSuggestion[]
---@field ScrollPrice fun(source: SkillUpScrollSource): number?
---@field ScrollSkill fun(recipeID: integer, source: SkillUpScrollSource): number?
---@field AddSourceLines fun(tooltip: GameTooltip, source: SkillUpScrollSource, first?: integer)
---@field NearestTrainer fun(profession: SkillUpContext, cap: number, byTravel?: boolean): integer?
---@field NearestVendor fun(itemID: integer, byTravel?: boolean): integer?
---@field NearestForRank fun(profession: SkillUpContext, rank: SkillUpRank, byTravel?: boolean): integer?, string
---@field AddNearest fun(tooltip: GameTooltip, label: string, npcID?: integer)
---@field AddCompanionHint fun(tooltip: GameTooltip)
---@field AnnounceUpdate fun()
---@field WHATS_NEW string
---@field FormatNet fun(copper: number, profit: boolean): string
---@field PriceAge fun(price: SkillUpPrice): number?
---@field PriceAgeText fun(price: SkillUpPrice): string
---@field PriceSourceText fun(price: SkillUpPrice): string
---@field UnpricedHint fun(): string
---@field ShowRecipeTooltip fun(_: SkillUpNamespace, row: SkillUpRecipeRow, data: SkillUpRecipeNodeData)
---@field AttachItemTooltips fun()
---@field AttachTrainer fun()
---@field SORT_OPTIONS string[][]
---@field CRAFT_VALUE_OPTIONS string[][]
---@field REAGENT_TOOLTIP_OPTIONS string[][]
---@field TITLE string
---@field L table<string, string> English phrase to the client locale's translation, else the phrase
---@field COLORS table<string, ColorMixin>
---@field Model SkillUpModel
---@field db SkillUpDB
---@field DEFAULTS SkillUpDefaults
---@field Thresholds table<integer, number[]>
---@field VendorPrices table<integer, number>
---@field RecipeData table<integer, SkillUpRecipe>
---@field RecipeScrolls table<integer, number[]> { scroll item, required skill } per recipe spell.
---@field RankBooks table<integer, number[][]> per skill line: { cap, book item, list price, required skill, level }.
---@field ItemGear table<integer, number[]>
---@field ItemSellPrices table<integer, number>
---@field RecipeNames table<integer, table<string, integer|false>>
---@field ProfessionSkillLines table<string, integer>
---@field TrainerFees table<integer, number[]>
---@field TrainerRanks table<integer, number[][]>
---@field TrainerInferred table<integer, number> classic-db's required skill, where the bundled one was moved from it.
---@field ProfessionTrainers table<integer, number[][]>
---@field GatheredBy table<integer, integer>
---@field NodeSkills table<string, number[]> { gathering skill line, required skill } per enUS herb or ore node name.
---@field ScrollDrops table<integer, number[][]>
---@field WorldDrops table<integer, boolean>
---@field Questie SkillUpQuestie
---@field AtlasLoot SkillUpAtlasLoot
---@field Catalogue SkillUpCatalogue
---@field InitCatalogue fun()

---@class SkillUpDefaults
---@field showRowText boolean
---@field showSkill boolean
---@field showTooltip boolean
---@field showCost boolean
---@field craftValue 'none'|'vendor'|'auction'
---@field valueGathered boolean
---@field sortMode 'blizzard'|'skill'|'chance'|'cost'
---@field showTrainer boolean
---@field showRouteTab boolean
---@field showTracker boolean
---@field showGearTab boolean
---@field merchantButton boolean
---@field reagentTooltip 'off'|'route'|'full'
---@field gatherTooltip boolean
---@field collectModes table<string, SkillUpCollectMode>
---@field showAllGear table<string, boolean>
---@field skippedRecipes table<string, table<integer, true>>
---@field whatsNew boolean
---@field companionHints boolean
---@field lastVersion string
---@field routeTargets table<integer, number>
---@field learned table<string, table<integer, boolean>>
---@field professionIDs table<string, integer>
---@field trackedProfessions table<integer, boolean>
---@field trainer table<integer, table<integer, number[]>> { fee, required skill, required skill the trainer showed? }
---@field trainerRanks table<integer, table<integer, number>>
---@field vendor table<integer, number>
---@field sellers table<integer, SkillUpSeller>
---@field builds string[] The client builds this install has run with, oldest first.

-- A vendor seen at its own window: where the player stood, and what it sold that the addon has a use for.
---@class SkillUpSeller
---@field name string
---@field side? 'A'|'H'
---@field map integer
---@field x number
---@field y number
---@field build? string The client build it was last seen on.
---@field items table<integer, true>

---@class SkillUpDB : SkillUpDefaults
---@field trackerHost? ForeverTrackerSettings
---@field showReagentTooltip? boolean Legacy migration only.
---@field scanAuctions? boolean Legacy migration only.
---@field tracked? table<integer, boolean> Legacy migration only.
---@field auctions? table Legacy migration only.
---@field gatherFree? boolean Legacy migration only.

---@type SkillUpDB
SkillUpForeverDB = nil

---@class SkillUpReagent
---@field itemID integer
---@field quantity number

---@class SkillUpRecipe : SkillUpSchematic
---@field skillLine integer

---@class SkillUpSchematic
---@field reagents SkillUpReagent[]
---@field output? SkillUpReagent|false

---@class SkillUpContext
---@field skillLine? integer
---@field skill number
---@field base number
---@field modifier number
---@field max number
---@field name? string
---@field capped boolean

---@class SkillUpProfession : SkillUpContext
---@field skillLine integer
---@field professionID? integer What GetProfessionInfo reports, which Forever's trade skill APIs take.
---@field name string
---@field icon fileID

---@class SkillUpCandidate
---@field recipeID integer
---@field thresholds number[]
---@field netCost? number
---@field skillUps? integer Skill points one craft grants, from the client.

-- A reagent a learned recipe makes for less than it costs to buy, as its own craft step.
---@class SkillUpSubCraft
---@field recipeID integer The recipe that makes the reagent.
---@field itemID integer The reagent it makes.
---@field crafts number How many crafts of it the parent step needs.
---@field made number How many it makes in all.

---@class SkillUpService : SkillUpCandidate
---@field fee number

---@class SkillUpSnapshot
---@field skill number
---@field target number
---@field recipes SkillUpCandidate[]

---@class SkillUpSegment
---@field recipeID integer
---@field fromSkill number
---@field toSkill number
---@field crafts number
---@field skillUps? integer

---@class SkillUpTraining
---@field recipeID integer
---@field fee number
---@field atSkill number

-- The plan's own shapes are in base skill, the number the Professions window shows.
---@class SkillUpPlanCraft
---@field recipeID integer
---@field from number
---@field to number
---@field crafts number
---@field points number Skill points the step reaches.
---@field skillUps integer Skill points one craft grants.
---@field color string The recipe's colour where the craft starts.
---@field station? string Where the client says the recipe is made.
---@field subcrafts SkillUpSubCraft[] The recipes that make its reagents, deepest first.

---@class SkillUpPlanTraining
---@field recipeID integer
---@field fee number
---@field usedAt number Where the plan first crafts it.
---@field reqSkill number What the trainer wants for it.
---@field cap number The cap a trainer must teach to for it.

-- One of a rank to train, a recipe to train or a craft, in the order they are walked.
---@class SkillUpRouteStep
---@field rank? SkillUpRank
---@field training? SkillUpPlanTraining
---@field subcraft? SkillUpSubCraft
---@field craft? SkillUpPlanCraft

---@class SkillUpBand
---@field color 'orange'|'yellow'|'green'|'grey'
---@field from number

---@class SkillUpRank
---@field name string
---@field cap number
---@field fee number The trainer's fee, or a book's price.
---@field book? integer The item that teaches the rank when no trainer does: bought and read, not trained.
---@field reqSkill number
---@field level number

---@class SkillUpRoute
---@field segments SkillUpSegment[]
---@field expectedCost number
---@field reachedSkill number
---@field excluded {unpriced: integer, recipes: integer[]} Known recipes left out for an unpriced reagent.
---@field stopReason? 'no_recipe'

---@class SkillUpTrainedRoute : SkillUpRoute
---@field training SkillUpTraining[]
---@field trainingCost number

-- What Core/Plan.lua returns: the levelling plan as a player reads it.
---@class SkillUpPlan
---@field profession SkillUpProfession
---@field target number
---@field reached number Where the crafts get to: short of the target when the known recipes run out.
---@field steps SkillUpRouteStep[]
---@field crafts SkillUpPlanCraft[]
---@field training SkillUpPlanTraining[]
---@field ranks SkillUpRank[]
---@field cost number Expected crafting cost plus every fee.
---@field unpriced integer Known recipes left out for an unpriced reagent.
---@field unpricedRecipes integer[]
---@field stopReason? 'no_recipe'

---@class SkillUpShoppingItem
---@field itemID integer
---@field count number

-- What a writer or a game event says changed, and the caches and views Core/Changes.lua keeps fresh.
---@alias SkillUpChange 'recipes'|'skill'|'professions'|'prices'|'bags'|'items'|'names'|'level'|'zone'|'merchant'|'fees'|'sources'|'target'|'tracking'|'settings'
---@alias SkillUpStale 'schematics'|'prices'|'plans'|'api'|'route'|'recipeList'|'tracker'|'trainer'|'routeTab'|'gear'|'tooltip'
---@alias SkillUpPriceSource 'vendor'|'auctionator'|'gather'
---@alias SkillUpCollectMode 'gather'|'auction'
---@alias SkillUpShoppingSource 'gather'|'vendor'|'auction'|'unknown'
---@class SkillUpPrice
---@field copper number
---@field source SkillUpPriceSource
---@field days? number Auctionator ages only: whole days since the newest observation.
---@field ageUnavailable? boolean Auctionator age API unavailable or failed, last-buyout prices only.
---@field profession? string Gathered reagents only.
---@field worth? 'auction'|'vendor' Gathered reagents valued at what they sell for: which price that is.

---@class SkillUpValue
---@field copper number
---@field source 'vendor'|'auction'
---@field quantity number

---@class SkillUpDescription
---@field thresholds? number[]
---@field color string
---@field chance? number
---@field cost? number
---@field value? SkillUpValue
---@field net? number
---@field perSkillUp? number

---@class SkillUpRecipeInfo
---@field recipeID integer
---@field learned? boolean
---@field canSkillUp? boolean
---@field relativeDifficulty? number

-- What Core/Live.lua records for one recipe from the client's own recipe read.
---@class SkillUpLiveRecipe
---@field thresholds? number[] Bundled orange/yellow/green with the client's live grey as the fourth.
---@field skillUps integer Skill points one craft grants now.

---@class SkillUpLocation
---@field name string
---@field label string
---@field map? integer
---@field x? number
---@field y? number

---@class SkillUpSuggestion
---@field recipeID integer
---@field source SkillUpScrollSource
---@field kind integer
---@field kindText string
---@field npcID? integer
---@field reach number Base skill.
---@field color string Its colour at the skill the route stopped at.

-- The fields of a suggestion that decide where its click goes; also a bare recipe scroll's source.
---@alias SkillUpSuggestionNPC { kind: integer?, source: SkillUpScrollSource?, npcID: integer? }

---@class SkillUpNeededItem
---@field itemID integer
---@field need number
---@field source SkillUpShoppingSource

---@class SkillUpTracked
---@field plan SkillUpPlan
---@field items SkillUpNeededItem[]

---@class SkillUpCraft
---@field text string
---@field recipeID? integer
---@field count? number How many the bags and the client allow now.
---@field planned? number How many the route asks for.
---@field to? number The skill the step reaches.
---@field missing? {itemID: integer, count: integer} The first reagent still short, and how many more.
---@field reason? string

---@alias SkillUpSortKey fun(info: TradeSkillRecipeInfo, ctx: SkillUpContext?): number

---@class SkillUpListEntry
---@field text string The name shown beside the icon.
---@field detail? string The supporting facts under the name, in the stock body font.
---@field color? ColorMixin The name's colour.
---@field icon? fileID|string
---@field iconColor? ColorMixin The stock icon border's tint, the item's quality where it has one.
---@field detailColor? ColorMixin
---@field tooltip? fun(tooltip: GameTooltip)
---@field click? fun(row: SkillUpListRow) A left click.
---@field menu? fun(owner: Region, root: RootMenuDescriptionProxy) A right-click's context menu, filled as MenuUtil fills one.

---@class SkillUpListRow : Button
---@field kind "row"
---@field entry SkillUpListEntry
---@field Icon Texture
---@field IconBorder Texture
---@field Text FontString
---@field Detail FontString
---@field tooltip? fun(tooltip: GameTooltip)
---@field click? fun(row: SkillUpListRow)
---@field menu? fun(owner: Region, root: RootMenuDescriptionProxy)
---@field UpdateTooltip fun(self: SkillUpListRow) called by the tooltip this row owns, a few times a second

---@class SkillUpListHeading : Frame
---@field kind "heading"
---@field Text FontString

---@class SkillUpListMessage : Frame
---@field kind "message"
---@field Text FontString

---@class SkillUpListElement
---@field kind "row"|"heading"|"message"
---@field text? string The heading's or message's line.
---@field color? ColorMixin The message's colour; the list's own grey when nil.
---@field entry? SkillUpListEntry The row's item.

---@class SkillUpList
---@field rows SkillUpListElement[] The elements of the last render, in order.
---@field scrollBox SkillUpScrollBox
---@field Begin fun(self: SkillUpList)
---@field Heading fun(self: SkillUpList, text: string)
---@field Message fun(self: SkillUpList, text: string, color?: ColorMixin)
---@field Add fun(self: SkillUpList, entry: SkillUpListEntry)
---@field Finish fun(self: SkillUpList)

---@class SkillUpCraftButton : Button
---@field recipeID? integer
---@field count? number
---@field title? string
---@field planned? number
---@field to? number
---@field reason? string

-- A class's list of craftable items, one entry a slot, newest first.
---@class SkillUpGearItem
---@field recipeID integer
---@field itemID integer
---@field name? string The client's item name, nil until its data has loaded.
---@field skillLine integer
---@field skill number? The skill at which the recipe can be learned, or nil when the data does not know.
---@field level number The item's required level.
---@field profession string
---@field learned boolean
---@field state "known"|"trainable"|"needs"|"other" What the character can do with the recipe.

---@class SkillUpGearSlot
---@field slot integer The slot group's position in the view.
---@field name string
---@field items SkillUpGearItem[]

-- What Gear.List needs to know about the character and the data.
---@class SkillUpGearQuery
---@field level number
---@field classID integer
---@field showAll boolean List rows the character cannot make yet too.
---@field learned fun(recipeID: integer): boolean
---@field professions table<integer, SkillUpProfession> The character's, by skill line.
---@field weaponSkills table<integer, number>? The weapon skill lines the character knows, or nil.
---@field name fun(itemID: integer): string?
---@field skill fun(recipeID: integer): number? The skill at which the recipe can be learned.
---@field professionName fun(skillLine: integer): string

---@class SkillUpGearPage : Frame
---@field ShowAll CheckButton
---@field ShowAllLabel FontString
---@field Slots SkillUpGearSlotButton[]
---@field Detail SkillUpGearDetail

-- A paper doll slot button: the item's icon, its quality border and the known mark the game uses.
---@class SkillUpGearSlotButton : CheckButton
---@field slot integer
---@field item SkillUpGearItem?
---@field icon Texture
---@field border Texture
---@field mark Texture
---@field select Texture

-- The pane's one action button, its text and the reason it is disabled.
---@class SkillUpGearAction : Button
---@field click (fun())?
---@field reason string?

-- The detail pane and the parts a render fills in.
---@class SkillUpGearDetail : Frame
---@field Body Frame
---@field Empty FontString
---@field Icon Texture
---@field Border Texture
---@field Name FontString
---@field Requirement FontString
---@field Learn FontString
---@field State FontString
---@field Reagents FontString
---@field ReagentRows SkillUpGearRow[]
---@field Action SkillUpGearAction
---@field Also FontString
---@field OtherRows SkillUpGearRow[]

-- A full-size item row the pane draws for a reagent or another item in the slot.
---@class SkillUpGearRow : Button
---@field Icon Texture
---@field Border Texture
---@field Text FontString
---@field Detail FontString
---@field tooltip (fun(tooltip: GameTooltip))?
---@field click (fun())?

---@class SkillUpPage : Frame
---@field Craft SkillUpCraftButton
---@field Profession DropdownButton
---@field Skill FontString
---@field Target EditBox
---@field Track Button
---@field Collect CheckButton
---@field CollectLabel FontString
---@field Vendor Button
---@field vendorItems integer[]
---@field RouteList SkillUpList
---@field ReagentList SkillUpList

---@class SkillUpBar : Frame
---@field track Frame
---@field segments Texture[]
---@field labels FontString[]
---@field marker Texture
---@field you FontString

---@class SkillUpUse
---@field recipeID integer
---@field t number[]
---@field skill number
---@field learned boolean

---@class SkillUpTrainerService
---@field name string
---@field kind string
---@field recipeID? integer
---@field ambiguous? boolean

-- A bundled trainer requirement a visit could prove wrong (/su trainers).
---@class SkillUpTrainerCheck
---@field skillLine integer
---@field recipeID integer
---@field bundled? number
---@field classic? number classic-db's, where the bundled one was moved from it.
---@field shown? number What a trainer showed.
---@field visited boolean Whether a trainer listed it, requirement or not.

---@class SkillUpTrainerState
---@field services SkillUpTrainerService[]
---@field ctx? SkillUpContext
---@field best? integer

---@alias SkillUpProviderState 'missing'|'unfit'|'waiting'|'ready'

-- What Questie says of an item: sorted NPC and quest IDs, and the recipe a scroll teaches.
---@class SkillUpItemSources
---@field vendors integer[]
---@field quests integer[]
---@field drops integer[]
---@field teaches? integer

---@class SkillUpSourceNPC
---@field name string
---@field side? ''|'A'|'H' Who can deal with it; nil when it is hostile to both.
---@field map? integer Its zone map, with x and y in 0-1.
---@field x? number
---@field y? number
---@field area? integer Its area, when it has no map point (a dungeon).
---@field world? {instance: integer, x: number, y: number}|false Its world position, worked out on first use.

---@class SkillUpSourceQuest
---@field title string
---@field side ''|'A'|'H'

-- Where a recipe's scroll comes from. The skill it needs is AtlasLoot's, so nil without it.
---@class SkillUpScrollSource
---@field item integer
---@field skill? number
---@field vendors integer[]
---@field quests integer[]
---@field drops number[][] { npc, chance % }, likeliest first.
---@field world boolean
