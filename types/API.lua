---@meta

-- SkillUp Forever's public API (version 1), read by other addons. Every table is
-- shared and read-only; a field SkillUp can't establish is nil.

---@alias SkillUpAPIStepKind 'buy'|'craft'|'train'|'gather'
---@alias SkillUpAPIReagentSource 'vendor'|'craft'|'gather'|'auction'

---@class SkillUpAPIStep
---@field kind SkillUpAPIStepKind
---@field text string Short imperative line, "Craft 3 Toughened Leather Gloves".
---@field detail? string "142 to 145", "Name, Zone · fee".
---@field itemID? integer Reagent to get, the craft's or trained recipe's product, or a rank's book to buy or read.
---@field spellID? integer Recipe to craft or train.
---@field count? number
---@field cost? number Copper: a purchase or training fee.
---@field nav boolean Navigate can route to the vendor or trainer.

---@class SkillUpAPIRecipe
---@field spellID integer
---@field itemID? integer
---@field name? string
---@field count number Crafts planned.
---@field fromRank number Base skill.
---@field toRank number
---@field learned boolean
---@field color? 'orange'|'yellow'|'green'|'grey'
---@field trainAt? number Base skill where the route first uses it, when it's still to train.
---@field cost? number Training fee in copper, when it's still to train.

---@class SkillUpAPIReagent
---@field itemID integer
---@field need number For the whole route.
---@field have number Bags and bank.
---@field source? SkillUpAPIReagentSource

---@class SkillUpAPIProfession
---@field name string Localized.
---@field skillLineID integer
---@field icon fileID
---@field rank number Base skill.
---@field maxRank number Current cap.
---@field title? string
---@field steps SkillUpAPIStep[] At most 3, in order.
---@field recipes SkillUpAPIRecipe[]
---@field reagents SkillUpAPIReagent[]

---@class SkillUpPublicAPI
---@field version integer
---@field Professions fun(): SkillUpAPIProfession[] Most actionable first.
---@field Navigate fun(skillLineID: integer, stepIndex: integer): boolean
---@field OpenRecipes fun(skillLineID: integer): boolean

---@class SkillUpPublicAddon
---@field API SkillUpPublicAPI
---@type SkillUpPublicAddon
SkillUpForever = nil
