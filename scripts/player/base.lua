require("config")
require("patterns")
stateHelper = require("stateHelper")
tableHelper = require("tableHelper")
local BasePlayer = class("BasePlayer")

function BasePlayer:__init(pid)
    self.dbPid = nil

    self.data =
    {
        login = {
            name = "",
            password = ""
        },
        settings = {
            admin = 0,
            consoleAllowed = "default",
            difficulty = "default"
        },
        character = {
            race = "",
            head = "",
            hair = "",
            gender = 1,
            class = "",
            birthsign = ""
        },
        location = {
            cell = "",
            posX = 0,
            posY = 0,
            posZ = 0,
            rotX = 0,
            rotZ = 0
        },
        stats = {
            level = 1,
            levelProgress = 0,
            healthBase = 1,
            healthCurrent = 1,
            magickaBase = 1,
            magickaCurrent = 1,
            fatigueBase = 1,
            fatigueCurrent = 1,
            bounty = 0
        }
    };
    self.data.customClass = {}
    self.data.attributes = {}
    self.data.attributeSkillIncreases = {}

    for i = 0, (tes3mp.GetAttributeCount() - 1) do
        local attributeName = tes3mp.GetAttributeName(i)
        self.data.attributes[attributeName] = 1
        self.data.attributeSkillIncreases[attributeName] = 0
    end

    self.data.skills = {}
    self.data.skillProgress = {}

    for i = 0, (tes3mp.GetSkillCount() - 1) do
        local skillName = tes3mp.GetSkillName(i)
        self.data.skills[skillName] = 1
        self.data.skillProgress[skillName] = 0
    end

    self.data.equipment = {}
    self.data.inventory = {}
    self.data.spellbook = {}
    self.data.factionRanks = {}
    self.data.factionExpulsion = {}
    self.data.books = {}
    self.data.mapExplored = {}

    self.initTimestamp = os.time()

    self.accountName = tes3mp.GetName(pid)
    self.pid = pid
    self.loggedIn = false
    self.tid_login = nil
    self.admin = 0
    self.hasAccount = nil -- TODO Check whether account file exists

    self.cellsLoaded = {}
end

function BasePlayer:Destroy()
    if self.tid_login ~= nil then
        tes3mp.StopTimer(self.tid_login)
        self.tid_login = nil
    end

    self.loggedIn = false
    self.hasAccount = nil
end

function BasePlayer:Kick()
    self:Destroy()
    tes3mp.Kick(self.pid)
end

function BasePlayer:Registered(passw)
    self.loggedIn = true
    self.data.login.password = passw
    self.data.settings.consoleAllowed = "default"
    if self.hasAccount == false then -- create account
        tes3mp.SetCharGenStage(self.pid, 1, 4)
    end
end

function BasePlayer:FinishLogin()
    self.loggedIn = true
    if self.hasAccount ~= false then -- load account
        self:LoadCharacter()
        self:LoadClass()
        self:LoadLevel()
        self:LoadAttributes()
        self:LoadSkills()
        self:LoadStatsDynamic()
        self:LoadBounty()
        self:LoadCell()
        self:LoadInventory()
        self:LoadEquipment()
        self:LoadSpellbook()
        self:LoadBooks()
        --self:LoadMap()
        self:LoadSettings()

        WorldInstance:LoadJournal(self.pid)

        if config.shareFactionRanks == true then
            WorldInstance:LoadFactionRanks(self.pid)
        else
            self:LoadFactionRanks()
        end

        if config.shareFactionExpulsion == true then
            WorldInstance:LoadFactionExpulsion(self.pid)
        else
            self:LoadFactionExpulsion()
        end

        WorldInstance:LoadTopics(self.pid)
        WorldInstance:LoadKills(self.pid)
    end
end

function BasePlayer:EndCharGen()
    self:SaveLogin()
    self:SaveCharacter()
    self:SaveClass()
    self:SaveStatsDynamic()
    self:SaveEquipment()
    self:CreateAccount()

    WorldInstance:LoadJournal(self.pid)
    
    if config.shareFactionRanks == true then
        WorldInstance:LoadFactionRanks(self.pid)
    else
        self:LoadFactionRanks()
    end

    if config.shareFactionExpulsion == true then
        WorldInstance:LoadFactionExpulsion(self.pid)
    else
        self:LoadFactionExpulsion()
    end

    WorldInstance:LoadTopics(self.pid)
    WorldInstance:LoadKills(self.pid)

    if config.defaultSpawnCell ~= nil then

        tes3mp.SetCell(self.pid, config.defaultSpawnCell)
        tes3mp.SendCell(self.pid)

        if config.defaultSpawnPos ~= nil and config.defaultSpawnRot ~= nil then
            tes3mp.SetPos(self.pid, config.defaultSpawnPos[1], config.defaultSpawnPos[2], config.defaultSpawnPos[3])
            tes3mp.SetRot(self.pid, config.defaultSpawnRot[1], config.defaultSpawnRot[2])
            tes3mp.SendPos(self.pid)
        end
    end
end

function BasePlayer:IsLoggedIn()
    return self.loggedIn
end

function BasePlayer:IsAdmin()
    return self.data.settings.admin == 2
end

function BasePlayer:IsModerator()
    return self.data.settings.admin >= 1
end

function BasePlayer:PromoteModerator(other)
    if self.IsAdmin() then
        other.data.settings.admin = 1
        return true
    end
    return false
end

function BasePlayer:GetHealthCurrent()
    self.data.stats.healthCurrent = tes3mp.GetHealthCurrent(self.pid)
    return self.data.stats.healthCurrent
end

function BasePlayer:SetHealthCurrent(health)
    self.data.stats.healthCurrent = health
    tes3mp.SetHealthCurrent(self.pid, health)
end

function BasePlayer:GetHealthBase()
    self.data.stats.healthBase = tes3mp.GetHealthBase(self.pid)
    return self.data.stats.healthBase
end

function BasePlayer:SetHealthBase(health)
    self.data.stats.healthBase = health
    tes3mp.SetHealthBase(self.pid, health)
end

function BasePlayer:HasAccount()
    return self.hasAccount
end

function BasePlayer:Message(message)
    tes3mp.SendMessage(self.pid, message, false)
end

function BasePlayer:CreateAccount()
    error("Not implemented")
end

function BasePlayer:Save()
    error("Not implemented")
end

function BasePlayer:Load()
    error("Not implemented")
end

function BasePlayer:SaveLogin()
    self.data.login.name = tes3mp.GetName(self.pid)
end

function BasePlayer:ProcessDeath()

    local deathReason = tes3mp.GetDeathReason(self.pid)

    tes3mp.LogMessage(1, "Original death reason was " .. deathReason)

    if deathReason == "suicide" then
        deathReason = "committed suicide"
    else
        deathReason = "was killed by " .. deathReason
    end

    local message = ("%s (%d) %s"):format(self.data.login.name, self.pid, deathReason)

    message = message .. ".\n"
    tes3mp.SendMessage(self.pid, message, true)

    self.tid_resurrect = tes3mp.CreateTimerEx("OnDeathTimeExpiration", time.seconds(config.deathTime), "i", self.pid)
    tes3mp.StartTimer(self.tid_resurrect);
end

function BasePlayer:Resurrect()
    local resurrectTypes = { REGULAR = 0, IMPERIAL_SHRINE = 1, TRIBUNAL_TEMPLE = 2}

    local currentResurrectType

    if config.respawnAtImperialShrine == true then
        if config.respawnAtTribunalTemple == true then
            if math.random() > 0.5 then
                currentResurrectType = resurrectTypes.IMPERIAL_SHRINE
            else
                currentResurrectType = resurrectTypes.TRIBUNAL_TEMPLE
            end
        else
            currentResurrectType = resurrectTypes.IMPERIAL_SHRINE
        end

    elseif config.respawnAtTribunalTemple == true then
        currentResurrectType = resurrectTypes.TRIBUNAL_TEMPLE

    elseif config.defaultRespawnCell ~= nil then
        currentResurrectType = resurrectTypes.REGULAR

        tes3mp.SetCell(self.pid, config.defaultRespawnCell)
        tes3mp.SendCell(self.pid)

        if config.defaultRespawnPos ~= nil and config.defaultRespawnRot ~= nil then
            tes3mp.SetPos(self.pid, config.defaultRespawnPos[1], config.defaultRespawnPos[2], config.defaultRespawnPos[3])
            tes3mp.SetRot(self.pid, config.defaultRespawnRot[1], config.defaultRespawnRot[2])
            tes3mp.SendPos(self.pid)
        end
    end

    local message = "You have been revived"

    if currentResurrectType == resurrectTypes.IMPERIAL_SHRINE then
        message = message .. " at the nearest Imperial shrine"
    elseif currentResurrectType == resurrectTypes.TRIBUNAL_TEMPLE then
        message = message .. " at the nearest Tribunal temple"
    end

    message = message .. ".\n"

    tes3mp.SetDeathPenaltyJailDays(self.pid, config.deathPenaltyJailDays)
    tes3mp.Resurrect(self.pid, currentResurrectType)
    tes3mp.SendMessage(self.pid, message, false)
end

function BasePlayer:LoadCharacter()
    tes3mp.SetRace(self.pid, self.data.character.race)
    tes3mp.SetHead(self.pid, self.data.character.head)
    tes3mp.SetHair(self.pid, self.data.character.hair)
    tes3mp.SetIsMale(self.pid, self.data.character.gender)
    tes3mp.SetBirthsign(self.pid, self.data.character.birthsign)

    tes3mp.SendBaseInfo(self.pid)
end

function BasePlayer:SaveCharacter()
    self.data.character.race = tes3mp.GetRace(self.pid)
    self.data.character.head = tes3mp.GetHead(self.pid)
    self.data.character.hair = tes3mp.GetHair(self.pid)
    self.data.character.gender = tes3mp.GetIsMale(self.pid)
    self.data.character.birthsign = tes3mp.GetBirthsign(self.pid)
end

function BasePlayer:LoadClass()
    if self.data.character.class ~= "custom" then
        tes3mp.SetDefaultClass(self.pid, self.data.character.class)
    elseif self.data.customClass ~= nil then
        tes3mp.SetClassName(self.pid, self.data.customClass.name)
        tes3mp.SetClassSpecialization(self.pid, self.data.customClass.specialization)

        if self.data.customClass.description ~= nil then
            tes3mp.SetClassDesc(self.pid, self.data.customClass.description)
        end

        local i = 0
        for value in string.gmatch(self.data.customClass.majorAttributes, patterns.commaSplit) do
            tes3mp.SetClassMajorAttribute(self.pid, i, tes3mp.GetAttributeId(value))
            i = i + 1
        end

        i = 0
        for value in string.gmatch(self.data.customClass.majorSkills, patterns.commaSplit) do
            tes3mp.SetClassMajorSkill(self.pid, i, tes3mp.GetSkillId(value))
            i = i + 1
        end

        i = 0
        for value in string.gmatch(self.data.customClass.minorSkills, patterns.commaSplit) do
            tes3mp.SetClassMinorSkill(self.pid, i, tes3mp.GetSkillId(value))
            i = i + 1
        end
    end

    tes3mp.SendClass(self.pid)
end

function BasePlayer:SaveClass()
    if tes3mp.IsClassDefault(self.pid) == 1 then
        self.data.character.class = tes3mp.GetDefaultClass(self.pid)
    else
        self.data.character.class = "custom"
        self.data.customClass.name = tes3mp.GetClassName(self.pid)
        self.data.customClass.description = tes3mp.GetClassDesc(self.pid):gsub("\n", "\\n")
        self.data.customClass.specialization = tes3mp.GetClassSpecialization(self.pid)
        local majorAttributes = {}
        local majorSkills = {}
        local minorSkills = {}

        for i = 0, 1, 1 do
            majorAttributes[i + 1] = tes3mp.GetAttributeName(tonumber(tes3mp.GetClassMajorAttribute(self.pid, i)))
        end

        for i = 0, 4, 1 do
            majorSkills[i + 1] = tes3mp.GetSkillName(tonumber(tes3mp.GetClassMajorSkill(self.pid, i)))
            minorSkills[i + 1] = tes3mp.GetSkillName(tonumber(tes3mp.GetClassMinorSkill(self.pid, i)))
        end

        self.data.customClass.majorAttributes = table.concat(majorAttributes, ", ")
        self.data.customClass.majorSkills = table.concat(majorSkills, ", ")
        self.data.customClass.minorSkills = table.concat(minorSkills, ", ")
    end
end

function BasePlayer:LoadStatsDynamic()
    tes3mp.SetHealthBase(self.pid, self.data.stats.healthBase)
    tes3mp.SetMagickaBase(self.pid, self.data.stats.magickaBase)
    tes3mp.SetFatigueBase(self.pid, self.data.stats.fatigueBase)
    tes3mp.SetHealthCurrent(self.pid, self.data.stats.healthCurrent)
    tes3mp.SetMagickaCurrent(self.pid, self.data.stats.magickaCurrent)
    tes3mp.SetFatigueCurrent(self.pid, self.data.stats.fatigueCurrent)

    tes3mp.SendStatsDynamic(self.pid)
end

function BasePlayer:SaveStatsDynamic()
    self.data.stats.healthBase = tes3mp.GetHealthBase(self.pid)
    self.data.stats.magickaBase = tes3mp.GetMagickaBase(self.pid)
    self.data.stats.fatigueBase = tes3mp.GetFatigueBase(self.pid)
    self.data.stats.healthCurrent = tes3mp.GetHealthCurrent(self.pid)
    self.data.stats.magickaCurrent = tes3mp.GetMagickaCurrent(self.pid)
    self.data.stats.fatigueCurrent = tes3mp.GetFatigueCurrent(self.pid)
end

function BasePlayer:LoadAttributes()
    for name, value in pairs(self.data.attributes) do
        tes3mp.SetAttributeBase(self.pid, tes3mp.GetAttributeId(name), value)
    end

    tes3mp.SendAttributes(self.pid)
end

function BasePlayer:SaveAttributes()
    for name in pairs(self.data.attributes) do
        local attributeId = tes3mp.GetAttributeId(name)
        self.data.attributes[name] = tes3mp.GetAttributeBase(self.pid, attributeId)
    end
end

function BasePlayer:LoadSkills()
    for name, value in pairs(self.data.skills) do
        tes3mp.SetSkillBase(self.pid, tes3mp.GetSkillId(name), value)
    end

    for name, value in pairs(self.data.skillProgress) do
        tes3mp.SetSkillProgress(self.pid, tes3mp.GetSkillId(name), value)
    end

    for name, value in pairs(self.data.attributeSkillIncreases) do
        tes3mp.SetSkillIncrease(self.pid, tes3mp.GetAttributeId(name), value)
    end

    tes3mp.SetLevelProgress(self.pid, self.data.stats.levelProgress)
    tes3mp.SendSkills(self.pid)
end

function BasePlayer:SaveSkills()
    for name in pairs(self.data.skills) do
        local skillId = tes3mp.GetSkillId(name)
        self.data.skills[name] = tes3mp.GetSkillBase(self.pid, skillId)
        self.data.skillProgress[name] = tes3mp.GetSkillProgress(self.pid, skillId)
    end

    for name in pairs(self.data.attributeSkillIncreases) do
        local attributeId = tes3mp.GetAttributeId(name)
        self.data.attributeSkillIncreases[name] = tes3mp.GetSkillIncrease(self.pid, attributeId)
    end

    self.data.stats.levelProgress = tes3mp.GetLevelProgress(self.pid)
end

function BasePlayer:LoadLevel()
    tes3mp.SetLevel(self.pid, self.data.stats.level)
    tes3mp.SendLevel(self.pid)
end

function BasePlayer:SaveLevel()
    self.data.stats.level = tes3mp.GetLevel(self.pid)
end

function BasePlayer:LoadBounty()
    tes3mp.SetBounty(self.pid, self.data.stats.bounty)
    tes3mp.SendBounty(self.pid)
end

function BasePlayer:SaveBounty()
    self.data.stats.bounty = tes3mp.GetBounty(self.pid)
end

function BasePlayer:LoadCell()
    local newCell = self.data.location.cell

    if newCell ~= nil then

        tes3mp.SetCell(self.pid, newCell)

        local pos = {0, 0, 0}
        local rot = {0, 0}
        pos[0] = self.data.location.posX
        pos[1] = self.data.location.posY
        pos[2] = self.data.location.posZ
        rot[0] = self.data.location.rotX
        rot[1] = self.data.location.rotZ

        tes3mp.SetPos(self.pid, pos[0], pos[1], pos[2])
        tes3mp.SetRot(self.pid, rot[0], rot[1])

        tes3mp.SendCell(self.pid)
        tes3mp.SendPos(self.pid)
    end
end

function BasePlayer:SaveCell()

    -- Keep this around to update old player files
    if self.data.mapExplored == nil then
        self.data.mapExplored = {}
    end

    local cell = tes3mp.GetCell(self.pid)
    self.data.location.cell = cell
    self.data.location.posX = tes3mp.GetPosX(self.pid)
    self.data.location.posY = tes3mp.GetPosY(self.pid)
    self.data.location.posZ = tes3mp.GetPosZ(self.pid)
    self.data.location.rotX = tes3mp.GetRotX(self.pid)
    self.data.location.rotZ = tes3mp.GetRotZ(self.pid)

    if tes3mp.IsInExterior(self.pid) == true then

        if tableHelper.containsValue(self.data.mapExplored, cell) == false then
            table.insert(self.data.mapExplored, cell)
        end
    end
end

function BasePlayer:LoadEquipment()

    for i = 0, tes3mp.GetEquipmentSize() - 1 do

        local currentItem = self.data.equipment[i]

        if currentItem ~= nil then
            tes3mp.EquipItem(self.pid, i, currentItem.refId, currentItem.count, currentItem.charge)
        else
            tes3mp.UnequipItem(self.pid, i)
        end
    end

    tes3mp.SendEquipment(self.pid)
end

function BasePlayer:SaveEquipment()

    self.data.equipment = {}

    for i = 0, tes3mp.GetEquipmentSize() - 1 do
        local itemRefId = tes3mp.GetEquipmentItemRefId(self.pid, i)

        if itemRefId ~= "" then
            self.data.equipment[i] = {
                refId = itemRefId,
                count = tes3mp.GetEquipmentItemCount(self.pid, i),
                charge = tes3mp.GetEquipmentItemCharge(self.pid, i)
            }
        end
    end
end

function BasePlayer:LoadInventory()

    if self.data.inventory == nil then
        self.data.inventory = {}
    end

    -- Send an empty initialized inventory to clear the player's existing items
    tes3mp.InitializeInventoryChanges(self.pid)
    tes3mp.SendInventoryChanges(self.pid)

    for index, currentItem in pairs(self.data.inventory) do

        if currentItem ~= nil then
            tes3mp.AddItem(self.pid, currentItem.refId, currentItem.count, currentItem.charge)
        end
    end

    tes3mp.SendInventoryChanges(self.pid)
end

function BasePlayer:SaveInventory()

    self.data.inventory = {}

    for i = 0, tes3mp.GetInventoryChangesSize(self.pid) - 1 do
        local itemRefId = tes3mp.GetInventoryItemRefId(self.pid, i)

        if itemRefId ~= "" then
            self.data.inventory[i] = {
                refId = itemRefId,
                count = tes3mp.GetInventoryItemCount(self.pid, i),
                charge = tes3mp.GetInventoryItemCharge(self.pid, i)
            }
        end
    end
end

function BasePlayer:LoadSpellbook()

    if self.data.spellbook == nil then
        self.data.spellbook = {}
    end

    -- Send an empty initialized spellbook to clear the player's existing spells
    tes3mp.InitializeSpellbookChanges(self.pid)
    tes3mp.SendSpellbookChanges(self.pid)

    for index, currentSpell in pairs(self.data.spellbook) do

        if currentSpell ~= nil then
            tes3mp.AddSpell(self.pid, currentSpell.spellId)
        end
    end

    tes3mp.SendSpellbookChanges(self.pid)
end

function BasePlayer:AddSpells()

    for i = 0, tes3mp.GetSpellbookChangesSize(self.pid) - 1 do
        local spellId = tes3mp.GetSpellId(self.pid, i)

        -- Only add new spell if we don't already have it
        if tableHelper.containsKeyValue(self.data.spellbook, "spellId", spellId, true) == false then
            tes3mp.LogMessage(1, "Adding spell " .. spellId .. " to " .. tes3mp.GetName(self.pid))
            local newSpell = {}
            newSpell.spellId = spellId
            table.insert(self.data.spellbook, newSpell)
        end
    end
end

function BasePlayer:RemoveSpells()

    for i = 0, tes3mp.GetSpellbookChangesSize(self.pid) - 1 do
        local spellId = tes3mp.GetSpellId(self.pid, i)

        -- Only print spell removal if the spell actually exists
        if tableHelper.containsKeyValue(self.data.spellbook, "spellId", spellId, true) == true then
            tes3mp.LogMessage(1, "Removing spell " .. spellId .. " from " .. tes3mp.GetName(self.pid))
            local foundIndex = tableHelper.getIndexByNestedKeyValue(self.data.spellbook, "spellId", spellId)
            self.data.spellbook[foundIndex] = nil
        end
    end

    tableHelper.cleanNils(self.data.spellbook)
end

function BasePlayer:SetSpells()

    self.data.spellbook = {}
    self:AddSpells()
end

function BasePlayer:SaveFactionRanks()
    stateHelper:SaveFactionRanks(self.pid, self)
end

function BasePlayer:LoadFactionRanks()
    stateHelper:LoadFactionRanks(self.pid, self)
end

function BasePlayer:SaveFactionExpulsion()
    stateHelper:SaveFactionExpulsion(self.pid, self)
end

function BasePlayer:LoadFactionExpulsion()
    stateHelper:LoadFactionExpulsion(self.pid, self)
end

function BasePlayer:LoadBooks()

    if self.data.books == nil then
        self.data.books = {}
    end

    tes3mp.InitializeBookChanges(self.pid)

    for index, bookId in pairs(self.data.books) do

        tes3mp.AddBook(self.pid, bookId)
    end

    tes3mp.SendBookChanges(self.pid)
end

function BasePlayer:AddBooks()

    for i = 0, tes3mp.GetBookChangesSize(self.pid) - 1 do
        local bookId = tes3mp.GetBookId(self.pid, i)

        -- Only add new book if we don't already have it
        if tableHelper.containsValue(self.data.books, bookId, false) == false then
            tes3mp.LogMessage(1, "Adding book " .. bookId .. " to " .. tes3mp.GetName(self.pid))
            table.insert(self.data.books, bookId)
        end
    end
end

function BasePlayer:LoadMap()

    if self.data.mapExplored == nil then
        self.data.mapExplored = {}
    end

    tes3mp.InitializeMapChanges(self.pid)

    for index, cellDescription in pairs(self.data.mapExplored) do

        tes3mp.AddCellExplored(self.pid, cellDescription)
    end

    tes3mp.SendMapChanges(self.pid)
end

function BasePlayer:GetConsole(state)
    return self.data.settings.consoleAllowed
end

function BasePlayer:GetDifficulty(state)
    return self.data.settings.difficulty
end

function BasePlayer:SetConsole(state)
    if state == nil or state == "default" then
        state = config.allowConsole
        self.data.settings.consoleAllowed = "default"
    else
        self.data.settings.consoleAllowed = state
    end

    tes3mp.SetConsoleAllow(self.pid, state)
end

function BasePlayer:SetDifficulty(difficulty)
    if difficulty == nil or difficulty == "default" then
        difficulty = config.difficulty
        self.data.settings.difficulty = "default"
    else
        self.data.settings.difficulty = difficulty    
    end

    tes3mp.SetDifficulty(self.pid, difficulty)
    tes3mp.LogMessage(3, "Set difficulty to " .. tostring(difficulty) .. " for " .. self.pid)
end

function BasePlayer:LoadSettings()
    
    self:SetConsole(self.data.settings.consoleAllowed)
    self:SetDifficulty(self.data.settings.difficulty)

    tes3mp.SendSettings(self.pid)
end

function BasePlayer:AddCellLoaded(cellDescription)

    -- Only add new loaded cell if we don't already have it
    if tableHelper.containsValue(self.cellsLoaded, cellDescription) == false then
        table.insert(self.cellsLoaded, cellDescription)
    end
end

function BasePlayer:RemoveCellLoaded(cellDescription)

    tableHelper.removeValue(self.cellsLoaded, cellDescription)
end

return BasePlayer
