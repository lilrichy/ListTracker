-- Create main object and load AceConsole so we can use console commands
ListTracker = LibStub("AceAddon-3.0"):NewAddon("ListTracker", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- Addon Version
local ltVersion = "1.1.1"

-- Create empty table for localization data
ListTracker.localize = {}
ListTracker.data = {}

-- Create addon message prefix
local PREFIX = "[ListTracker]"

-- Use variables for numeric weekdays, matches return from date(%w) + 1
local SUNDAY = 1
local MONDAY = 2
local TUESDAY = 3
local WEDNESDAY = 4
local THURSDAY = 5
local FRIDAY = 6
local SATURDAY = 7

local expandNormalTexture = "Interface\\BUTTONS\\UI-PlusButton-Up.blp"
local expandPushedTexture = "Interface\\BUTTONS\\UI-PlusButton-Down.blp"
local contractNormalTexture = "Interface\\BUTTONS\\UI-MinusButton-Up.blp"
local contractPushedTexture = "Interface\\BUTTONS\\UI-MinusButton-Down.blp"
local expandHighlightTexture = "Interface\\BUTTONS\\UI-PlusButton-Hilight.png"

local intervalConverter = {600, 1200, 1800, 3600}

-- Create stack/pools for unused, previously created interface objects
ListTracker.checklistFrameCheckboxPool = {}
ListTracker.checklistFrameTextPool = {}
ListTracker.checklistFrameHeaderExpandPool = {}
ListTracker.checklistFrameHeaderTextPool = {}
ListTracker.checklistFrameHeaderCheckboxPool = {}

-- Create color variables
ListTracker.selectedEntryColor = "|cffFFB90F"
ListTracker.managerPanelHeight = 300

ListTracker.timerId = nil
ListTracker.currentDay = nil
ListTracker.selectedManagerFrameText = nil
ListTracker.selectedManagerFrameList = nil
ListTracker.ShowObjectivesWindow = nil

-- Create minimap icon
ListTracker.ListTrackerLDB = LibStub("LibDataBroker-1.1"):NewDataObject("ListTrackerDO", {
    type = "data source",
    text = "ListTracker",
    icon = "Interface\\RAIDFRAME\\ReadyCheck-Ready.blp",
    OnTooltipShow = function(tt)
        tt:AddLine("ListTracker - " .. ltVersion)
        tt:AddLine("|cffffff00" .. "Left Click to hide/show frame")
        tt:AddLine("|cffffff00" .. "Right Click to open options")
    end,
    OnClick = function(self, button)
        ListTracker:HandleIconClick(button)
    end
})
ListTracker.icon = LibStub("LibDBIcon-1.0")

-- Set database default values
ListTracker.defaults = {
    profile = {
        version = ltVersion,
        icon = {
            hide = false
        },
        framePosition = {
            x = 0,
            y = 0,
            anchor = "CENTER",
            hidden = false
        },
        locked = false,
        hideObjectives = false,
        showListHeaders = true,
        hideCompleted = false,
        timestamp = nil,
        dailyResetTime = 1,
        weeklyResetDay = 3,
        resetPollInterval = 5,
        setScale = 1,
        lists = {
            [1] = {
                name = "Default",
                expanded = true,
                entries = {}
            }
        }
    }
}

-- Initialize addon, called directly after the addon is fully loaded
function ListTracker:OnInitialize()
    -- Create database with default values
    self.db = LibStub("AceDB-3.0"):New("ListTrackerDB", self.defaults);
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshEverything")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshEverything")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshEverything")

    -- Register minimap icon
    self.icon:Register("ListTrackerDO", self.ListTrackerLDB, self.db.profile.icon)

    -- Register addon message prefix
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Register chat commands
    self:RegisterChatCommand("lt", "HandleChatMessageCommands")
    self:RegisterChatCommand("ListTracker", "HandleChatMessageCommands")
end

function ListTracker:UpdateVisibility()
    self:UpdateVisibilityOnChecklistFrame(self.db.profile.hideCompleted)
    self:UpdateEntryPositionsOnChecklistFrame()
    self:UpdateVisibilityForChecklistFrame()
    self:UpdateVisibilityForIcon(self.db.profile.icon.hide)
end

function ListTracker:HandleChatMessageCommands(msg)
    local command, text = msg:match("(%S+)%s*(%S*)")
    if command == "show" then
        if text == "icon" then
            self.db.profile.icon.hide = false
        else
            if text == "completed" then
                self.db.profile.hideCompleted = false
            else
                self.db.profile.framePosition.hidden = false
            end
        end
        self:UpdateVisibility()
    elseif command == "hide" then
        if text == "icon" then
            self.db.profile.icon.hide = true
        else
            if text == "completed" then
                self.db.profile.hideCompleted = true
            else
                self.db.profile.framePosition.hidden = true
            end
        end
        self:UpdateVisibility()
    elseif command == "toggle" then
        if text == "icon" then
            self.db.profile.icon.hide = not self.db.profile.icon.hide
        else
            if text == "completed" then
                self.db.profile.hideCompleted = not self.db.profile.hideCompleted
            else
                self.db.profile.framePosition.hidden = not self.db.profile.framePosition.hidden
            end
        end
        self:UpdateVisibility()
    elseif command == "lock" then
        self.db.profile.locked = true
    elseif command == "unlock" then
        self.db.profile.locked = false
    elseif command == "check" and text == "time" then
        self:UpdateForNewDateAndTime()
    elseif command == "options" then
        InterfaceOptionsFrame_OpenToCategory(self.checklistOptionsFrame)
    elseif command == "manager" then
        InterfaceOptionsFrame_OpenToCategory(self.checklistManagerFrame)
    elseif command == "profiles" then
        InterfaceOptionsFrame_OpenToCategory(self.checklistProfilesFrame)
    elseif command == "help" then
        self:Print("\"/lt show\" : shows checklist")
        self:Print("\"/lt hide\" : hides checklist")
        self:Print("\"/lt show icon\" : shows minimap icon (requires ui restart to take effect)")
        self:Print("\"/lt hide icon\" : hides minimap icon (requires ui restart to take effect)")
        self:Print("\"/lt lock\" : locks checklist position")
        self:Print("\"/lt unlock\" : unlocks checklist position")
        self:Print("\"/lt check time\" : check if entries should be reset")
        self:Print("\"/lt show completed\" : show completed entries")
        self:Print("\"/lt hide completed\" : hide completed entries")
        self:Print("\"/lt options\" : opens options dialog")
        self:Print("\"/lt profiles\" : opens profiles dialog")
        self:Print("\"/lt manager\" : opens manager dialog")
    else
        self:Print("Usage: \"/lt <command> <identifier>\"")
        self:Print("Type: \"/lt help\" for a list of commands")
    end
end

-- Called when the addon is enabled
function ListTracker:OnEnable()

    self.ShowObjectivesWindow = ObjectiveTrackerFrame.Show
    ObjectiveTrackerFrame.Show = self.ObjectiveTrackerFrameShow

    -- Notify user that ListTracker is enabled, give config command
    self:Print("List Tracker v", ltVersion .. "", " enabled.")

    self:CheckCurrentDateAndTime(true)

    self:ResetTimer()

    -- Initialize number of entries that will fit in interface options panel
    self.maxEntries = math.floor((InterfaceOptionsFramePanelContainer:GetHeight() - self.managerPanelHeight) / 20)

    -- Create options frame
    self:CreateManagerFrame()

    -- Create checklist frame
    self:CreateChecklistFrame()

    -- TODO Research this ->  ObjectiveTrackerFrame.Show=function() end
end

-- Called when timer interval changes
function ListTracker:ResetTimer()
    -- Remove old timer
    if self.timerId then
        self:CancelTimer(self.timerId)
        self.timerId = nil
    end

    if self.db.profile.resetPollInterval ~= 1 then
        self.timerId = self:ScheduleRepeatingTimer("UpdateForNewDateAndTime",
                           intervalConverter[self.db.profile.resetPollInterval - 1])
    end
end

-- Updates checklist entries based on new time and/or day
function ListTracker:UpdateForNewDateAndTime()
    if ListTracker:CheckCurrentDateAndTime(false) then
        ListTracker:UpdateEntryPositionsOnChecklistFrame()
    end
    ListTracker:UpdateEntryCompletedOnChecklistFrame()
    ListTracker:UpdateVisibilityOnChecklistFrame(self.db.profile.hideCompleted)
end

-- Resets completed quests given the current day and time
function ListTracker:CheckCurrentDateAndTime(firstTime)
    -- Save current weekday
    local oldDay = self.currentDay
    local entriesChanged = false
    self.currentDay = tonumber(date("%w")) + 1
    local currentListReset = false
    local currentTime = tonumber(date("%Y%m%d%H%M%S"))

    -- If first time starting application
    if not self.db.profile.timestamp then
        self.db.profile.timestamp = tonumber(date("%Y%m%d")) * 1000000
    end

    -- Set reset time to user selected time on current day
    local resetTime = tonumber(date("%Y%m%d")) * 1000000 + (self.db.profile.dailyResetTime - 1) * 10000

    -- Check if we have completed quests for the current day on this character
    if self.db.profile.timestamp < resetTime and
        (currentTime > resetTime or (currentTime - 1000000) > self.db.profile.timestamp) then
        -- Has not been opened yet today, should reset completed quests 
        for listId, list in ipairs(self.db.profile.lists) do
            for entryId, entry in ipairs(list.entries) do
                if not entry.manual then
                    if not entry.weekly then
                        entry.completed = false
                        if not firstTime and self.checklistFrame.lists[listId] and
                            self.checklistFrame.lists[listId].entries[entryId] and
                            self.checklistFrame.lists[listId].entries[entryId].checkbox then
                            self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(false)
                        end
                        currentListReset = true
                    else
                        if self.db.profile.weeklyResetDay == self.currentDay then
                            entry.completed = false
                            if not firstTime and self.checklistFrame.lists[listId] and
                                self.checklistFrame.lists[listId].entries[entryId] and
                                self.checklistFrame.lists[listId].entries[entryId].checkbox then
                                self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(false)
                            end
                            currentListReset = true
                        end
                    end
                end
            end
            if currentListReset then
                list.completed = false
                if not firstTime and self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].checkbox then
                    self.checklistFrame.lists[listId].checkbox:SetChecked(false)
                end
                currentListReset = false
            end
        end
        -- Update timestamp to future, we already updated today
        self.db.profile.timestamp = resetTime
    end

    -- Check if entries should be removed or added due to day change
    if not firstTime and oldDay ~= self.currentDay then
        for listId, list in ipairs(self.db.profile.lists) do
            for entryId, entry in ipairs(list.entries) do
                if entry.days[oldDay] ~= entry.days[self.currentDay] then
                    self:UpdateEntryOnChecklistFrame(listId, entryId, entry.checked)
                    entriesChanged = true
                end
            end
        end
    end

    return entriesChanged
end

-- Create the main checklist frame 
function ListTracker:CreateChecklistFrame()
    self.checklistFrame = CreateFrame("Frame", "ChecklistFrame", UIParent)
    self.checklistFrame:SetMovable(true)
    self.checklistFrame:EnableMouse(true)
    self.checklistFrame:SetClampedToScreen(true)
    self.checklistFrame:RegisterForDrag("LeftButton")
    self.checklistFrame:SetScript("OnDragStart", function(frame)
        if not ListTracker.db.profile.locked then
            frame:StartMoving()
        end
    end)
    self.checklistFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        ListTracker.db.profile.framePosition.anchor, _, _, ListTracker.db.profile.framePosition.x, ListTracker.db
            .profile.framePosition.y = frame:GetPoint()
    end)

    -- 9.0 Update to Backdrop
    if not self.checklistFrame.SetBackdropColor then
        Mixin(self.checklistFrame, BackdropTemplateMixin)
    end
    self.checklistFrame:SetBackdropColor(0, 0, 0, 1)
    self.checklistFrame:SetScale(self.db.profile.setScale)
    self.checklistFrame:SetHeight(200)
    self.checklistFrame:SetWidth(200)
    self.checklistFrame:SetAlpha(1.0)

    ListTracker:UpdateVisibilityForChecklistFrame()

    -- Create empty array to store quest list buttons
    self.checklistFrame.lists = {}

    -- Create the title text
    local title = self.checklistFrame:CreateFontString("TitleText", nil, "GameFontNormalLarge")
    title:SetText("|cffFFB90FList Tracker|r")
    title:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", -4, 0)
    title:Show()

    self:CreateChecklistFrameElements()

    self.checklistFrame:SetHeight(32)
    self.checklistFrame:SetPoint(self.db.profile.framePosition.anchor, nil, self.db.profile.framePosition.anchor,
        self.db.profile.framePosition.x, self.db.profile.framePosition.y - 16)
end

function ListTracker:RemoveChecklistFrameElements()
    local listId = table.getn(self.checklistFrame.lists)
    while listId > 0 do
        self:RemoveListFromChecklistFrame(listId)
        listId = listId - 1
    end
end

function ListTracker:CreateChecklistFrameElements()

    -- Adjust offset for beginning of list
    local offset = 18

    -- Create entry tracking frame contents
    for listId, list in pairs(self.db.profile.lists) do

        -- Create empty table for list
        self.checklistFrame.lists[listId] = {}
        self.checklistFrame.lists[listId].entries = {}

        -- Determine if we should show list elements
        local show = true

        if self.db.profile.showListHeaders then

            if not list.completed or not self.db.profile.hideCompleted then
                -- Create header expand button
                if table.getn(self.checklistFrameHeaderExpandPool) > 0 then
                    self.checklistFrame.lists[listId].expand = self.checklistFrameHeaderExpandPool[1]
                    table.remove(self.checklistFrameHeaderExpandPool, 1)
                else
                    self.checklistFrame.lists[listId].expand =
                        CreateFrame("Button", nil, self.checklistFrame, "UICheckButtonTemplate")
                    self.checklistFrame.lists[listId].expand:SetWidth(12)
                    self.checklistFrame.lists[listId].expand:SetHeight(12)
                    self.checklistFrame.lists[listId].expand:SetScript("OnClick", function(self)
                        ListTracker:ToggleChecklistFrameListExpand(self)
                    end)
                    self.checklistFrame.lists[listId].expand:SetHighlightTexture(expandHighlightTexture)
                end

                if self.db.profile.lists[listId].expanded then
                    self.checklistFrame.lists[listId].expand:SetNormalTexture(contractNormalTexture)
                    self.checklistFrame.lists[listId].expand:SetPushedTexture(contractPushedTexture)
                else
                    self.checklistFrame.lists[listId].expand:SetNormalTexture(expandNormalTexture)
                    self.checklistFrame.lists[listId].expand:SetPushedTexture(expandPushedTexture)
                end

                self.checklistFrame.lists[listId].expand:SetPoint("TOPLEFT", 1, -offset - 1)
                self.checklistFrame.lists[listId].expand.listId = listId
                self.checklistFrame.lists[listId].expand:Show()

                -- Create header checkbox
                if table.getn(self.checklistFrameHeaderCheckboxPool) > 0 then
                    self.checklistFrame.lists[listId].checkbox = self.checklistFrameHeaderCheckboxPool[1]
                    table.remove(self.checklistFrameHeaderCheckboxPool, 1)
                else
                    -- Create checkbox for list
                    self.checklistFrame.lists[listId].checkbox =
                        CreateFrame("CheckButton", nil, self.checklistFrame, "UICheckButtonTemplate")
                    self.checklistFrame.lists[listId].checkbox:SetWidth(16)
                    self.checklistFrame.lists[listId].checkbox:SetHeight(16)
                    self.checklistFrame.lists[listId].checkbox:SetChecked(false)
                    self.checklistFrame.lists[listId].checkbox:SetScript("OnClick", function(self)
                        ListTracker:ToggleChecklistFrameListCheckbox(self)
                    end)
                end

                -- Change checkbox properties to match the new list
                self.checklistFrame.lists[listId].checkbox:SetPoint("TOPLEFT", 12, -offset + 1)
                self.checklistFrame.lists[listId].checkbox.listId = listId
                self.checklistFrame.lists[listId].checkbox:SetChecked(self.db.profile.lists[listId].completed)
                self.checklistFrame.lists[listId].checkbox:Show()

                -- Check if we can reuse a label
                if table.getn(self.checklistFrameHeaderTextPool) > 0 then
                    self.checklistFrame.lists[listId].headerText = self.checklistFrameHeaderTextPool[1]
                    table.remove(self.checklistFrameHeaderTextPool, 1)
                else
                    self.checklistFrame.lists[listId].headerText =
                        self.checklistFrame:CreateFontString("ListHeader" .. listId, nil, "GameFontNormal")
                end

                -- Change header text for new entry
                self.checklistFrame.lists[listId].headerText:SetText(self.db.profile.lists[listId].name)
                self.checklistFrame.lists[listId].headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 30,
                    -offset - 1)
                self.checklistFrame.lists[listId].headerText:Show()

                offset = offset + 18

                if not self.db.profile.lists[listId].expanded then
                    show = false
                end
            else
                show = false
            end
        end

        for entryId, entry in pairs(list.entries) do

            if entry.checked and entry.days[self.currentDay] then
                self:CreateEntryInChecklistFrame(listId, entryId, offset)

                if not show or (entry.completed and self.db.profile.hideCompleted) then
                    self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
                    self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
                else
                    offset = offset + 16
                end
            end
        end
    end
end

function ListTracker:CreateEntryInChecklistFrame(listId, entryId, offset)
    -- Create empty table for new entry
    self.checklistFrame.lists[listId].entries[entryId] = {}

    local horizontalOffset = 7

    if self.db.profile.showListHeaders then
        horizontalOffset = horizontalOffset + 12
    end

    -- Check if we can reuse a checkbox
    if table.getn(self.checklistFrameCheckboxPool) > 0 then
        self.checklistFrame.lists[listId].entries[entryId].checkbox = self.checklistFrameCheckboxPool[1]
        table.remove(self.checklistFrameCheckboxPool, 1)
    else
        -- Create checkbox for quest
        self.checklistFrame.lists[listId].entries[entryId].checkbox =
            CreateFrame("CheckButton", nil, self.checklistFrame, "UICheckButtonTemplate")
        self.checklistFrame.lists[listId].entries[entryId].checkbox:SetWidth(16)
        self.checklistFrame.lists[listId].entries[entryId].checkbox:SetHeight(16)
        self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(false)
        self.checklistFrame.lists[listId].entries[entryId].checkbox:SetScript("OnClick", function(self)
            ListTracker:ToggleSingleChecklistFrameCheckbox(self)
        end)
    end

    -- Change checkbox properties to match the new quest
    self.checklistFrame.lists[listId].entries[entryId].checkbox:SetPoint("TOPLEFT", horizontalOffset, -offset + 1)
    self.checklistFrame.lists[listId].entries[entryId].checkbox.entryId = entryId
    self.checklistFrame.lists[listId].entries[entryId].checkbox.listId = listId
    self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(
        self.db.profile.lists[listId].entries[entryId].completed)
    self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()

    -- Check if we can reuse a label
    if table.getn(self.checklistFrameTextPool) > 0 then
        self.checklistFrame.lists[listId].entries[entryId].headerText = self.checklistFrameTextPool[1]
        table.remove(self.checklistFrameTextPool, 1)
    else
        self.checklistFrame.lists[listId].entries[entryId].headerText =
            self.checklistFrame:CreateFontString("QuestHeader" .. entryId, nil, "ChatFontNormal")
    end

    -- Change header text for new entry
    self.checklistFrame.lists[listId].entries[entryId].headerText:SetText(
        self.db.profile.lists[listId].entries[entryId].text)
    self.checklistFrame.lists[listId].entries[entryId].headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT",
        horizontalOffset + 16, -offset)
    self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
end

-- Creates the UI elements of a list on the Checklist Frame
function ListTracker:CreateListOnChecklistFrame(listId, offset)
    -- Create header expand button
    if table.getn(self.checklistFrameHeaderExpandPool) > 0 then
        self.checklistFrame.lists[listId].expand = self.checklistFrameHeaderExpandPool[1]
        table.remove(self.checklistFrameHeaderExpandPool, 1)
    else
        self.checklistFrame.lists[listId].expand = CreateFrame("Button", nil, self.checklistFrame,
                                                       "UICheckButtonTemplate")
        self.checklistFrame.lists[listId].expand:SetWidth(12)
        self.checklistFrame.lists[listId].expand:SetHeight(12)
        self.checklistFrame.lists[listId].expand:SetScript("OnClick", function(self)
            ListTracker:ToggleChecklistFrameListExpand(self)
        end)
        self.checklistFrame.lists[listId].expand:SetHighlightTexture(expandHighlightTexture)
    end

    if self.db.profile.lists[listId].expanded then
        self.checklistFrame.lists[listId].expand:SetNormalTexture(contractNormalTexture)
        self.checklistFrame.lists[listId].expand:SetPushedTexture(contractPushedTexture)
    else
        self.checklistFrame.lists[listId].expand:SetNormalTexture(expandNormalTexture)
        self.checklistFrame.lists[listId].expand:SetPushedTexture(expandPushedTexture)
    end

    self.checklistFrame.lists[listId].expand:SetPoint("TOPLEFT", 1, -offset - 1)
    self.checklistFrame.lists[listId].expand.listId = listId
    self.checklistFrame.lists[listId].expand:Show()

    -- Create header checkbox
    if table.getn(self.checklistFrameHeaderCheckboxPool) > 0 then
        self.checklistFrame.lists[listId].checkbox = self.checklistFrameHeaderCheckboxPool[1]
        table.remove(self.checklistFrameHeaderCheckboxPool, 1)
    else
        -- Create checkbox for list
        self.checklistFrame.lists[listId].checkbox = CreateFrame("CheckButton", nil, self.checklistFrame,
                                                         "UICheckButtonTemplate")
        self.checklistFrame.lists[listId].checkbox:SetWidth(16)
        self.checklistFrame.lists[listId].checkbox:SetHeight(16)
        self.checklistFrame.lists[listId].checkbox:SetChecked(false)
        self.checklistFrame.lists[listId].checkbox:SetScript("OnClick", function(self)
            ListTracker:ToggleChecklistFrameListCheckbox(self)
        end)
    end

    -- Change checkbox properties to match the new list
    self.checklistFrame.lists[listId].checkbox:SetPoint("TOPLEFT", 12, -offset + 1)
    self.checklistFrame.lists[listId].checkbox.listId = listId
    self.checklistFrame.lists[listId].checkbox:SetChecked(self.db.profile.lists[listId].completed)
    self.checklistFrame.lists[listId].checkbox:Show()

    -- Check if we can reuse a label
    if table.getn(self.checklistFrameHeaderTextPool) > 0 then
        self.checklistFrame.lists[listId].headerText = self.checklistFrameHeaderTextPool[1]
        table.remove(self.checklistFrameHeaderTextPool, 1)
    else
        self.checklistFrame.lists[listId].headerText = self.checklistFrame:CreateFontString("ListHeader" .. listId, nil,
                                                           "GameFontNormal")
    end

    -- Change header text for new entry
    self.checklistFrame.lists[listId].headerText:SetText(self.db.profile.lists[listId].name)
    self.checklistFrame.lists[listId].headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 30, -offset - 1)
    self.checklistFrame.lists[listId].headerText:Show()
end

-- Updates a list header in the Checklist Frame
function ListTracker:UpdateListOnChecklistFrame(listId)
    -- Check if list is already represented on checklist frame, if not, create it
    if not self.checklistFrame.lists[listId] then
        self.checklistFrame.lists[listId] = {}
        self.checklistFrame.lists[listId].entries = {}
    end

    -- Check if UI elements have been created on checklist frame, if not, create them
    if not self.checklistFrame.lists[listId].checkbox then
        self:CreateListOnChecklistFrame(listId, 0)
    end

    self.checklistFrame.lists[listId].checkbox:Show()
    self.checklistFrame.lists[listId].headerText:Show()
    self.checklistFrame.lists[listId].expand:Show()
end

-- Updates a single entry in the Checklist Frame
function ListTracker:UpdateEntryOnChecklistFrame(listId, entryId, checked)

    -- Show the requested entry if it is checked	
    if checked and self.db.profile.lists[listId].entries[entryId].days[self.currentDay] then
        -- Check if list is already represented on checklist frame, if not, create it
        if not self.checklistFrame.lists[listId] then
            self.checklistFrame.lists[listId] = {}
            self.checklistFrame.lists[listId].entries = {}
        end

        -- Check if entry has been created on checklist frame, if not, create it
        if not self.checklistFrame.lists[listId].entries[entryId] then
            self:CreateEntryInChecklistFrame(listId, entryId, 0)
        end

        self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
        self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
    else
        -- If it is unchecked, hide the entry if it exists
        -- if not checked then
        if self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].entries[entryId] then
            self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
            self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
        end

        -- [elseif self.db.profile.lists[listId].entries[entryId].days[self.currentDay] then
        if self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].entries[entryId] then
            self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
            self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
        end
    end
end

-- Moves all entries to their correct position in the checklist frame
function ListTracker:UpdateEntryPositionsOnChecklistFrame()

    -- Calculate offset
    local offset = 18

    local horizontalOffset = 7

    if self.db.profile.showListHeaders then
        horizontalOffset = horizontalOffset + 12
    end

    -- Move all remaining entries to the new correct position
    for listId, list in pairs(self.checklistFrame.lists) do
        if self.db.profile.showListHeaders then
            if not self.db.profile.lists[listId].completed or not self.db.profile.hideCompleted then
                if not list.expand then
                    self:CreateListOnChecklistFrame(listId, offset)
                else
                    list.checkbox:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 12, -offset + 1)
                    list.checkbox.listId = listId
                    list.expand:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 1, -offset - 1)
                    list.expand.listId = listId
                    list.headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 30, -offset - 1)
                end
                offset = offset + 18
            else
                if list.expand then
                    list.expand:Hide()
                    list.checkbox:Hide()
                    list.headerText:Hide()
                end
            end
        end
        if not self.db.profile.showListHeaders or self.db.profile.lists[listId].expanded then
            for entryId, entry in pairs(list.entries) do
                if entry and
                    (self.db.profile.lists[listId].entries[entryId].checked and self.db.profile.lists[listId].expanded) and
                    (not self.db.profile.lists[listId].entries[entryId].completed or not self.db.profile.hideCompleted) then
                    entry.checkbox:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", horizontalOffset, -offset + 1)
                    entry.checkbox.listId = listId
                    entry.checkbox.entryId = entryId
                    entry.checkbox:Show()
                    entry.headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", horizontalOffset + 16, -offset)
                    entry.headerText:Show()
                    offset = offset + 16
                else
                    if entry.checkbox then
                        entry.checkbox:Hide()
                        entry.headerText:Hide()
                    end
                end
            end
        else
            for entryId, entry in pairs(list.entries) do
                if entry then
                    entry.checkbox:Hide()
                    entry.headerText:Hide()
                end
            end
        end
    end
end

-- Updates all checkboxes on the checklist frame
function ListTracker:UpdateEntryCompletedOnChecklistFrame()
    for listId, list in pairs(self.checklistFrame.lists) do
        local allCompleted = true
        for entryId, entry in pairs(list.entries) do
            if self.db.profile.lists[listId].entries[entryId].completed then
                entry.checkbox:SetChecked(true)
            else
                allCompleted = false
            end
        end
        if self.db.profile.lists[listId].completed ~= allCompleted then
            self.db.profile.lists[listId].completed = allCompleted
        end
        if list.checkbox then
            list.checkbox:SetChecked(allCompleted)
        end
    end
end

-- Removes only the list header from the Checklist Frame
function ListTracker:RemoveListHeaderFromChecklistFrame(listId)
    -- Check if list exists
    if not self.checklistFrame.lists[listId] then
        return
    end

    -- Check if UI objects exist, if they do, recycle them
    if self.checklistFrame.lists[listId].checkbox then
        self.checklistFrame.lists[listId].checkbox:Hide()
        self.checklistFrame.lists[listId].headerText:Hide()
        self.checklistFrame.lists[listId].expand:Hide()

        -- Store interface elements in respective pools for potential reuse
        table.insert(self.checklistFrameHeaderCheckboxPool, self.checklistFrame.lists[listId].checkbox)
        table.insert(self.checklistFrameHeaderTextPool, self.checklistFrame.lists[listId].headerText)
        table.insert(self.checklistFrameHeaderExpandPool, self.checklistFrame.lists[listId].expand)

        -- Nil out entries so they no longer exist in the frame
        self.checklistFrame.lists[listId].checkbox = nil
        self.checklistFrame.lists[listId].headerText = nil
        self.checklistFrame.lists[listId].expand = nil
    end
end

-- Removes a whole list from the Checklist Frame
function ListTracker:RemoveListFromChecklistFrame(listId)

    -- Check if list has been created on checklist frame, if not, do nothing
    if not self.checklistFrame.lists[listId] then
        return
    end

    -- Remove all list entries from checklist frame
    local entryId = table.getn(self.checklistFrame.lists[listId].entries)
    while entryId > 0 do
        self:RemoveEntryFromChecklistFrame(listId, entryId)
        entryId = entryId - 1
    end

    -- Remove the header UI elements if they exist
    self:RemoveListHeaderFromChecklistFrame(listId)

    -- Remove list from table
    table.remove(self.checklistFrame.lists, listId)
end

-- Removes a single entry from the Checklist Frame
function ListTracker:RemoveEntryFromChecklistFrame(listId, entryId)
    -- Check if entry has been created on checklist frame, if not, do nothing
    if not self.checklistFrame.lists[listId] or not self.checklistFrame.lists[listId].entries[entryId] then
        return
    end

    -- Hide interface elements for entry
    self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
    self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()

    -- Store interface elements in respective pools for potential reuse
    table.insert(self.checklistFrameCheckboxPool, self.checklistFrame.lists[listId].entries[entryId].checkbox)
    table.insert(self.checklistFrameTextPool, self.checklistFrame.lists[listId].entries[entryId].headerText)

    -- Nil out entries so they no longer exist in the frame
    self.checklistFrame.lists[listId].entries[entryId].checkbox = nil
    self.checklistFrame.lists[listId].entries[entryId].headerText = nil

    table.remove(self.checklistFrame.lists[listId].entries, entryId)

    if table.getn(self.checklistFrame.lists[listId].entries) <= 0 and not self.db.profile.showListHeaders then
        self:RemoveListHeaderFromChecklistFrame(listId)
        -- Remove list from table
        table.remove(self.checklistFrame.lists, listId)
    end
end

-- Create the options frame under the WoW interface->addons menu
function ListTracker:CreateManagerFrame()
    -- Create addon options frame
    self.checklistManagerFrame = CreateFrame("Frame", "ChecklistManagerFrame", InterfaceOptionsFramePanelContainer)
    self.checklistManagerFrame.name = "ListTracker"
    self.checklistManagerFrame:SetAllPoints(InterfaceOptionsFramePanelContainer)
    self.checklistManagerFrame:Hide()
    InterfaceOptions_AddCategory(self.checklistManagerFrame)

    -- Create addon profiles options frame
    self.checklistProfilesOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("ListTracker: " .. self.checklistProfilesOptions.name,
        self.checklistProfilesOptions)
    self.checklistProfilesFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
                                      "ListTracker: " .. self.checklistProfilesOptions.name,
                                      self.checklistProfilesOptions.name, "ListTracker")

    local function getOpt(info)
        return ListTracker.db.profile[info[#info]]
    end

    local function setOpt(info, value)
        ListTracker.db.profile[info[#info]] = value
        return ListTracker.db.profile[info[#info]]
    end

    -- Create options frame
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("ListTracker: Options", {
        type = "group",
        name = "Options",
        args = {
            general = {
                type = "group",
                inline = true,
                name = "",
                args = {
                    all = {
                        type = "group",
                        inline = true,
                        name = "Resets",
                        order = 10,
                        args = {
                            weeklyResetDayLabel = {
                                type = "description",
                                name = "Weekly reset day:",
                                order = 10
                            },
                            weeklyResetDay = {
                                type = "select",
                                name = "",
                                values = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"},
                                order = 20,
                                style = "dropdown",
                                get = getOpt,
                                set = function(info, value)
                                    ListTracker.db.profile.weeklyResetDay = value
                                    ListTracker:UpdateForNewDateAndTime()
                                end
                            },
                            dailyResetTimeLabel = {
                                type = "description",
                                name = "Daily reset time (in local time):",
                                order = 30
                            },
                            dailyResetTime = {
                                type = "select",
                                name = "",
                                values = {"00:00", "01:00", "02:00", "03:00", "04:00", "05:00", "06:00", "07:00",
                                          "08:00", "09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00",
                                          "16:00", "17:00", "18:00", "19:00", "20:00", "21:00", "22:00", "23:00"},
                                order = 40,
                                width = "half",
                                get = getOpt,
                                set = function(info, value)
                                    ListTracker.db.profile.dailyResetTime = value
                                    ListTracker:UpdateForNewDateAndTime()
                                end
                            },
                            resetPollIntervalLabel = {
                                type = "description",
                                name = "How often to check for a reset due to new time or day",
                                order = 50
                            },
                            resetPollInterval = {
                                type = "select",
                                name = "",
                                values = {"Never", "10 Minutes", "20 Minutes", "30 Minutes", "1 Hour"},
                                order = 60,
                                get = getOpt,
                                set = function(info, value)
                                    ListTracker.db.profile.resetPollInterval = value
                                    ListTracker:ResetTimer()
                                end
                            },
                            checkTimeLabel = {
                                type = "description",
                                order = 70,
                                name = "Use this to manually check for a reset"
                            },
                            checkTime = {
                                type = "execute",
                                order = 80,
                                name = "Check Time",
                                func = function()
                                    ListTracker:UpdateForNewDateAndTime()
                                end
                            }
                        }
                    },
                    frames = {
                        type = "group",
                        inline = true,
                        name = "ListTracker Frame Options",
                        order = 20,
                        args = {
                            locked = {
                                type = "toggle",
                                name = "Lock Frame",
                                order = 10,
                                get = getOpt,
                                set = setOpt
                            },
                            hidden = {
                                type = "toggle",
                                name = "Hide Frame",
                                order = 20,
                                get = function(info)
                                    return ListTracker.db.profile.framePosition.hidden
                                end,
                                set = function(info, value)
                                    ListTracker.db.profile.framePosition.hidden = value
                                    ListTracker:UpdateVisibilityForChecklistFrame()
                                end
                            },
                            showListHeaders = {
                                type = "toggle",
                                name = "Show list headers",
                                order = 30,
                                get = getOpt,
                                set = function(info, value)
                                    ListTracker.db.profile.showListHeaders = value
                                    if value then
                                        for listId, _ in pairs(ListTracker.db.profile.lists) do
                                            ListTracker:UpdateListOnChecklistFrame(listId)
                                        end
                                    else
                                        for listId, _ in pairs(ListTracker.db.profile.lists) do
                                            ListTracker:RemoveListHeaderFromChecklistFrame(listId)
                                        end
                                    end
                                    -- Update positions because of visibility change
                                    ListTracker:UpdateEntryPositionsOnChecklistFrame()
                                end
                            },
                            hideCompleted = {
                                type = "toggle",
                                name = "Hide Completed",
                                order = 40,
                                get = getOpt,
                                set = function(info, value)
                                    ListTracker.db.profile.hideCompleted = value
                                    ListTracker:UpdateVisibilityOnChecklistFrame(value)
                                    ListTracker:UpdateEntryPositionsOnChecklistFrame()
                                end
                            },
                            setScale = {
                                type = "range",
                                name = "Set List Scale",
                                min = .5,
                                max = 2.5,
                                bigStep = .1,
                                order = 50,
                                get = getOpt,
                                set = function(info, value)
                                    ListTracker.db.profile.setScale = value
                                    ListTracker:UpdateScale(value)
                                end
                            }
                        }
                    },
                    minimap = {
                        type = "group",
                        inline = true,
                        name = "Minimap Icon",
                        order = 30,
                        args = {
                            iconLabel = {
                                type = "description",
                                name = "Requires UI restart to take effect",
                                order = 10
                            },
                            icon = {
                                type = "toggle",
                                name = "Hide Minimap Icon",
                                order = 20,
                                get = function(info)
                                    return ListTracker.db.profile.icon.hide
                                end,
                                set = function(info, value)
                                    ListTracker.db.profile.icon.hide = value
                                end
                            }
                        }
                    },
                    utilities = {
                        type = "group",
                        inline = true,
                        name = "Utilities",
                        order = 40,
                        args = {
                            resetLabel = {
                                type = "description",
                                name = "Requires UI restart to take effect",
                                order = 10
                            },
                            resetPosition = {
                                type = "execute",
                                order = 20,
                                name = "Reset List Position",
                                func = function()
                                    ListTracker.db.profile.framePosition = ListTracker.defaults.profile.framePosition
                                    ListTracker.checklistFrame:SetPoint(ListTracker.db.profile.framePosition.anchor,
                                        nil, ListTracker.db.profile.framePosition.anchor,
                                        ListTracker.db.profile.framePosition.x,
                                        ListTracker.db.profile.framePosition.y - 16)
                                end
                            },
                            memoryLabel = {
                                type = "description",
                                name = "Use this when you have significantly changed the checklist to free up memory",
                                order = 30
                            },
                            memory = {
                                type = "execute",
                                order = 40,
                                name = "Clear Trash",
                                func = function()
                                    collectgarbage("collect")
                                end
                            }
                        }
                    }
                }
            }
        }
    })
    self.checklistOptionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ListTracker: Options", "Options",
                                     "ListTracker")

    local checklistManagerListLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    checklistManagerListLabel:SetPoint("TOPLEFT", 10, -10)
    checklistManagerListLabel:SetPoint("TOPRIGHT", 0, -10)
    checklistManagerListLabel:SetJustifyH("LEFT")
    checklistManagerListLabel:SetHeight(18)
    checklistManagerListLabel:SetText("New List")

    local checklistManagerListTextFieldLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                                   "GameTooltipTextSmall")
    checklistManagerListTextFieldLabel:SetPoint("TOPLEFT", 10, -30)
    checklistManagerListTextFieldLabel:SetPoint("TOPRIGHT", 0, -30)
    checklistManagerListTextFieldLabel:SetJustifyH("LEFT")
    checklistManagerListTextFieldLabel:SetHeight(18)
    checklistManagerListTextFieldLabel:SetText("Create a new list category")

    -- Add entry creation form to options frame
    self.checklistManagerListTextField = CreateFrame("EditBox", "ChecklistManagerListTextField",
                                             self.checklistManagerFrame, "InputBoxTemplate")
    self.checklistManagerListTextField:SetSize(450, 28)
    self.checklistManagerListTextField:SetPoint("TOPLEFT", 20, -44)
    self.checklistManagerListTextField:SetMaxLetters(255)
    self.checklistManagerListTextField:SetMultiLine(false)
    self.checklistManagerListTextField:SetAutoFocus(false)
    self.checklistManagerListTextField:SetScript("OnEnterPressed", function(self)
        ListTracker:CreateChecklistList()
    end)

    self.checklistManagerListTextFieldButton = CreateFrame("Button", nil, self.checklistManagerFrame,
                                                   "UIPanelButtonTemplate")
    self.checklistManagerListTextFieldButton:SetSize(100, 24)
    self.checklistManagerListTextFieldButton:SetPoint("TOPLEFT", 500, -46)
    self.checklistManagerListTextFieldButton:SetText("Create")
    self.checklistManagerListTextFieldButton:SetScript("OnClick", function(frame)
        ListTracker:CreateChecklistList()
    end)

    local checklistManagerEntryLabel =
        self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    checklistManagerEntryLabel:SetPoint("TOPLEFT", 10, -76)
    checklistManagerEntryLabel:SetPoint("TOPRIGHT", 0, -76)
    checklistManagerEntryLabel:SetJustifyH("LEFT")
    checklistManagerEntryLabel:SetHeight(18)
    checklistManagerEntryLabel:SetText("New Item")

    local checklistManagerTextFieldLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                               "GameTooltipTextSmall")
    checklistManagerTextFieldLabel:SetPoint("TOPLEFT", 10, -95)
    checklistManagerTextFieldLabel:SetPoint("TOPRIGHT", 0, -95)
    checklistManagerTextFieldLabel:SetJustifyH("LEFT")
    checklistManagerTextFieldLabel:SetHeight(18)
    checklistManagerTextFieldLabel:SetText("Create a new list item and add it to the currently selected list category")

    -- Add entry creation form to options frame
    self.checklistManagerTextField = CreateFrame("EditBox", "ChecklistManagerTextField", self.checklistManagerFrame,
                                         "InputBoxTemplate")
    self.checklistManagerTextField:SetSize(355, 28)
    self.checklistManagerTextField:SetPoint("TOPLEFT", 20, -109)
    self.checklistManagerTextField:SetMaxLetters(255)
    self.checklistManagerTextField:SetMultiLine(false)
    self.checklistManagerTextField:SetAutoFocus(false)
    self.checklistManagerTextField:SetScript("OnEnterPressed", function(self)
        ListTracker:CreateChecklistEntry()
    end)

    local checklistManagerWeeklyLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                            "GameTooltipTextSmall")
    checklistManagerWeeklyLabel:SetPoint("TOPLEFT", 400, -95)
    checklistManagerWeeklyLabel:SetPoint("TOPRIGHT", 0, -95)
    checklistManagerWeeklyLabel:SetJustifyH("LEFT")
    checklistManagerWeeklyLabel:SetHeight(18)
    checklistManagerWeeklyLabel:SetText("Reset, leave blank for daily")

    self.checklistManagerWeeklyCheckbox = CreateFrame("CheckButton", nil, self.checklistManagerFrame,
                                              "UICheckButtonTemplate")
    self.checklistManagerWeeklyCheckbox:SetPoint("TOPLEFT", 400, -110)
    self.checklistManagerWeeklyCheckbox:SetWidth(25)
    self.checklistManagerWeeklyCheckbox:SetHeight(25)
    self.checklistManagerWeeklyCheckbox:SetScript("OnClick", function(frame)
        ListTracker.checklistManagerManualCheckbox:SetChecked(false)
    end)

    local checklistManagerWeeklyText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    checklistManagerWeeklyText:SetPoint("TOPLEFT", 425, -115)
    checklistManagerWeeklyText:SetHeight(18)
    checklistManagerWeeklyText:SetText("Weekly")

    self.checklistManagerManualCheckbox = CreateFrame("CheckButton", nil, self.checklistManagerFrame,
                                              "UICheckButtonTemplate")
    self.checklistManagerManualCheckbox:SetPoint("TOPLEFT", 500, -110)
    self.checklistManagerManualCheckbox:SetWidth(25)
    self.checklistManagerManualCheckbox:SetHeight(25)
    self.checklistManagerManualCheckbox:SetScript("OnClick", function(frame)
        ListTracker.checklistManagerWeeklyCheckbox:SetChecked(false)
    end)

    local checklistManagerManualText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    checklistManagerManualText:SetPoint("TOPLEFT", 525, -115)
    checklistManagerManualText:SetHeight(18)
    checklistManagerManualText:SetText("Manual")

    self.checklistManagerTextFieldButton = CreateFrame("Button", nil, self.checklistManagerFrame,
                                               "UIPanelButtonTemplate")
    self.checklistManagerTextFieldButton:SetSize(100, 24)
    self.checklistManagerTextFieldButton:SetPoint("TOPLEFT", 500, -135)
    self.checklistManagerTextFieldButton:SetText("Create")
    self.checklistManagerTextFieldButton:SetScript("OnClick", function(frame)
        ListTracker:CreateChecklistEntry()
    end)

    -- Add list category title
    local checklistManagerTitle = self.checklistManagerFrame:CreateFontString("ManagerTitleText", nil,
                                      "GameFontNormalLarge")
    checklistManagerTitle:SetText("|cffFFB90FList Category|r")
    checklistManagerTitle:SetPoint("TOPLEFT", self.checklistManagerFrame, "TOPLEFT", 10, -215)
    checklistManagerTitle:Show()

    -- Add checklist list dropdown
    self.checklistManagerListDropDown = CreateFrame("Button", "ChecklistManagerListDropDown",
                                            self.checklistManagerFrame, "UIDropDownMenuTemplate")
    self.checklistManagerListDropDown:SetPoint("TOPLEFT", self.checklistManagerFrame, "TOPLEFT", 120, -210)
    self.checklistManagerListDropDown:Show()

    -- Initialize drop down
    UIDropDownMenu_Initialize(self.checklistManagerListDropDown, function(self, level)
        -- Gather list of names
        local listNames = {}

        for _, list in pairs(ListTracker.db.profile.lists) do
            table.insert(listNames, list.name)
        end

        local info = UIDropDownMenu_CreateInfo()
        for k, v in pairs(listNames) do
            info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.value = v
            info.func = function(self)
                ListTracker.selectedManagerFrameList = self:GetID()
                UIDropDownMenu_SetSelectedID(ListTracker.checklistManagerListDropDown, self:GetID())
                ListTracker:UpdateEntriesForScrollFrame()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(self.checklistManagerListDropDown, 200);
    UIDropDownMenu_SetButtonWidth(self.checklistManagerListDropDown, 224)
    UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, 1)
    UIDropDownMenu_JustifyText(self.checklistManagerListDropDown, "LEFT")

    -- Set initial selected list
    if table.getn(self.db.profile.lists) > 0 then
        self.selectedManagerFrameList = self.selectedManagerFrameList or 1
    end

    -- Delete Category Button
    self.checklistManagerDeleteListButton = CreateFrame("Button", nil, self.checklistManagerFrame,
                                                "UIPanelButtonTemplate")
    self.checklistManagerDeleteListButton:SetPoint("TOPLEFT", 500, -210)
    self.checklistManagerDeleteListButton:SetSize(100, 24)
    self.checklistManagerDeleteListButton:SetText("Delete List")
    self.checklistManagerDeleteListButton:SetScript("OnClick", function(self)
        ListTracker:DeleteSelectedList()
    end)

    -- Labels for Checkboxes
    local checklistManagerWeeklyLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                            "GameTooltipTextSmall")
    checklistManagerWeeklyLabel:SetPoint("TOPLEFT", 40, -235)
    checklistManagerWeeklyLabel:SetPoint("TOPRIGHT", 0, -235)
    checklistManagerWeeklyLabel:SetJustifyH("LEFT")
    checklistManagerWeeklyLabel:SetHeight(18)
    checklistManagerWeeklyLabel:SetText("Weekly")

    local checklistManagerManualLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                            "GameTooltipTextSmall")
    checklistManagerManualLabel:SetPoint("TOPLEFT", 85, -235)
    checklistManagerManualLabel:SetPoint("TOPRIGHT", 0, -235)
    checklistManagerManualLabel:SetJustifyH("LEFT")
    checklistManagerManualLabel:SetHeight(18)
    checklistManagerManualLabel:SetText("Manual")

    local checklistManagerShownLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                           "GameTooltipTextSmall")
    checklistManagerShownLabel:SetPoint("TOPLEFT", 135, -235)
    checklistManagerShownLabel:SetPoint("TOPRIGHT", 0, -235)
    checklistManagerShownLabel:SetJustifyH("LEFT")
    checklistManagerShownLabel:SetHeight(18)
    checklistManagerShownLabel:SetText("Shown")

    local checklistManagerMoveLabel =
        self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    checklistManagerMoveLabel:SetPoint("TOPLEFT", 180, -235)
    checklistManagerMoveLabel:SetPoint("TOPRIGHT", 0, -235)
    checklistManagerMoveLabel:SetJustifyH("LEFT")
    checklistManagerMoveLabel:SetHeight(18)
    checklistManagerMoveLabel:SetText("Move")

    local checklistManagerDeleteLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                            "GameTooltipTextSmall")
    checklistManagerDeleteLabel:SetPoint("TOPLEFT", 230, -235)
    checklistManagerDeleteLabel:SetPoint("TOPRIGHT", 0, -235)
    checklistManagerDeleteLabel:SetJustifyH("LEFT")
    checklistManagerDeleteLabel:SetHeight(18)
    checklistManagerDeleteLabel:SetText("Delete")

    local checklistManagerItemsLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY",
                                           "GameTooltipTextSmall")
    checklistManagerItemsLabel:SetPoint("TOPLEFT", 275, -235)
    checklistManagerItemsLabel:SetPoint("TOPRIGHT", 0, -235)
    checklistManagerItemsLabel:SetJustifyH("LEFT")
    checklistManagerItemsLabel:SetHeight(18)
    checklistManagerItemsLabel:SetText("Items")

    -- Create scrollable frame
    self.checklistManagerFrameScroll = CreateFrame("ScrollFrame", "checklistManagerFrameScroll",
                                           self.checklistManagerFrame, "FauxScrollFrameTemplate")
    local sizeX, sizeY = self.checklistManagerFrame:GetSize()
    self.checklistManagerFrameScroll:SetSize(sizeX, sizeY - self.managerPanelHeight)
    self.checklistManagerFrameScroll:SetPoint("CENTER", -30, -95)
    self.checklistManagerFrameScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 20, function()
            ListTracker:UpdateEntriesForScrollFrame()
        end)
    end)
    self.checklistManagerFrameScroll:SetScript("OnShow", function()
        ListTracker:UpdateEntriesForScrollFrame()
    end)

    -- Create empty tables
    self.checklistManagerFrameShownCheckboxes = {}
    self.checklistManagerFrameText = {}
    self.checklistManagerFrameClickable = {}
    self.checklistManagerFrameWeeklyCheckboxes = {}
    self.checklistManagerFrameManualCheckboxes = {}
    self.checklistManagerFrameDeleteIcon = {}
    self.checklistManagerFrameMoveUpIcon = {}
    self.checklistManagerFrameMoveDownIcon = {}

    -- Set up vertical offset for checkbox list
    local offset = self.managerPanelHeight - 50

    -- Create a set amount of checkboxes and labels for reuse on the scrollable frame
    for i = 1, self.maxEntries do

        -- Weekly Checkboxes in scrollable frame
        self.checklistManagerFrameWeeklyCheckboxes[i] = CreateFrame("CheckButton", nil, self.checklistManagerFrame,
                                                            "UICheckButtonTemplate")
        self.checklistManagerFrameWeeklyCheckboxes[i]:SetPoint("TOPLEFT", 40, -offset)
        self.checklistManagerFrameWeeklyCheckboxes[i]:SetWidth(25)
        self.checklistManagerFrameWeeklyCheckboxes[i]:SetHeight(25)
        self.checklistManagerFrameWeeklyCheckboxes[i]:SetChecked(false)
        self.checklistManagerFrameWeeklyCheckboxes[i]:SetScript("OnClick", function(self)
            ListTracker:ToggleChecklistManagerWeeklyCheckbox(self)
        end)
        self.checklistManagerFrameWeeklyCheckboxes[i]:Hide()

        -- Manual Checkboxes in scrollable frame
        self.checklistManagerFrameManualCheckboxes[i] = CreateFrame("CheckButton", nil, self.checklistManagerFrame,
                                                            "UICheckButtonTemplate")
        self.checklistManagerFrameManualCheckboxes[i]:SetPoint("TOPLEFT", 85, -offset)
        self.checklistManagerFrameManualCheckboxes[i]:SetWidth(25)
        self.checklistManagerFrameManualCheckboxes[i]:SetHeight(25)
        self.checklistManagerFrameManualCheckboxes[i]:SetChecked(false)
        self.checklistManagerFrameManualCheckboxes[i]:SetScript("OnClick", function(self)
            ListTracker:ToggleChecklistManagerManualCheckbox(self)
        end)
        self.checklistManagerFrameManualCheckboxes[i]:Hide()

        -- Shown Checkbox
        self.checklistManagerFrameShownCheckboxes[i] = CreateFrame("CheckButton", nil, self.checklistManagerFrame,
                                                           "UICheckButtonTemplate")
        self.checklistManagerFrameShownCheckboxes[i]:SetPoint("TOPLEFT", 135, -offset)
        self.checklistManagerFrameShownCheckboxes[i]:SetWidth(25)
        self.checklistManagerFrameShownCheckboxes[i]:SetHeight(25)
        self.checklistManagerFrameShownCheckboxes[i]:SetChecked(false)
        self.checklistManagerFrameShownCheckboxes[i]:SetScript("OnClick", function(self)
            ListTracker:ToggleChecklistManagerShownCheckbox(self)
        end)
        self.checklistManagerFrameShownCheckboxes[i]:Hide()

        -- Clickable Frame
        self.checklistManagerFrameClickable[i] = CreateFrame("Frame", "ClickableFrame" .. i, self.checklistManagerFrame)
        self.checklistManagerFrameClickable[i]:SetPoint("TOPLEFT", 275, -offset)
        self.checklistManagerFrameClickable[i]:SetWidth(300)
        self.checklistManagerFrameClickable[i]:SetHeight(25)
        self.checklistManagerFrameClickable[i]:SetScript("OnEnter", function(self)
            self.inside = true
        end)
        self.checklistManagerFrameClickable[i]:SetScript("OnLeave", function(self)
            self.inside = false
        end)
        self.checklistManagerFrameClickable[i]:SetScript("OnMouseUp", function(self)
            if self.inside then
                if ListTracker.checklistManagerFrameText[i]:IsShown() then
                    ListTracker.checklistManagerFrameText[i]:SetText(
                        ListTracker.selectedEntryColor .. ListTracker.checklistManagerFrameText[i]:GetText())
                    ListTracker:ResetSelectedManagerFrameText()
                    ListTracker.selectedManagerFrameText = i
                end
            end
        end)

        self.checklistManagerFrameText[i] =
            self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        self.checklistManagerFrameText[i]:SetPoint("TOPLEFT", 275, -offset - 5)
        self.checklistManagerFrameText[i]:SetText("")
        self.checklistManagerFrameText[i]:Hide()

        -- Icon for Move Up Button
        self.checklistManagerFrameMoveUpIcon[i] = CreateFrame("BUTTON", nil, self.checklistManagerFrame,
                                                      "SecureHandlerClickTemplate");
        self.checklistManagerFrameMoveUpIcon[i]:SetSize(25, 25)
        self.checklistManagerFrameMoveUpIcon[i]:SetPoint("TOPLEFT", 175, -offset)
        self.checklistManagerFrameMoveUpIcon[i]:RegisterForClicks("AnyUp")
        self.checklistManagerFrameMoveUpIcon[i]:SetNormalTexture("Interface\\MINIMAP\\UI-Minimap-MinimizeButtonUp-Up")
        self.checklistManagerFrameMoveUpIcon[i]:SetHighlightTexture(
            "Interface\\MINIMAP\\UI-Minimap-MinimizeButtonUp-Highlight")
        self.checklistManagerFrameMoveUpIcon[i]:SetPushedTexture("Interface\\MINIMAP\\UI-Minimap-MinimizeButtonUp-Down")
        self.checklistManagerFrameMoveUpIcon[i]:SetScript("OnClick", function(self)
            ListTracker:MoveSelectedEntryUp(self)
        end)
        self.checklistManagerFrameMoveUpIcon[i]:Hide()

        -- Icon for Move Down Button
        self.checklistManagerFrameMoveDownIcon[i] = CreateFrame("BUTTON", nil, self.checklistManagerFrame,
                                                        "SecureHandlerClickTemplate");
        self.checklistManagerFrameMoveDownIcon[i]:SetSize(25, 25)
        self.checklistManagerFrameMoveDownIcon[i]:SetPoint("TOPLEFT", 195, -offset)
        self.checklistManagerFrameMoveDownIcon[i]:RegisterForClicks("AnyUp")
        self.checklistManagerFrameMoveDownIcon[i]:SetNormalTexture(
            "Interface\\MINIMAP\\UI-Minimap-MinimizeButtonDown-Up")
        self.checklistManagerFrameMoveDownIcon[i]:SetHighlightTexture(
            "Interface\\MINIMAP\\UI-Minimap-MinimizeButtonDown-Highlight")
        self.checklistManagerFrameMoveDownIcon[i]:SetPushedTexture(
            "Interface\\MINIMAP\\UI-Minimap-MinimizeButtonDown-Down")
        self.checklistManagerFrameMoveDownIcon[i]:SetScript("OnClick", function(self)
            ListTracker:MoveSelectedEntryDown(self)
        end)
        self.checklistManagerFrameMoveDownIcon[i]:Hide()

        -- Icon for Delete button
        self.checklistManagerFrameDeleteIcon[i] = CreateFrame("BUTTON", nil, self.checklistManagerFrame,
                                                      "SecureHandlerClickTemplate");
        self.checklistManagerFrameDeleteIcon[i]:SetSize(25, 25)
        self.checklistManagerFrameDeleteIcon[i]:SetPoint("TOPLEFT", 230, -offset)
        self.checklistManagerFrameDeleteIcon[i]:RegisterForClicks("AnyUp")
        self.checklistManagerFrameDeleteIcon[i]:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        self.checklistManagerFrameDeleteIcon[i]:SetHighlightTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_7")
        self.checklistManagerFrameDeleteIcon[i]:SetScript("OnClick", function(self)
            ListTracker:DeleteSelectedEntry(self)
        end)
        self.checklistManagerFrameDeleteIcon[i]:Hide()

        offset = offset + 20
    end
end

-- Removes the selected list from the manager frame and database
function ListTracker:DeleteSelectedList()

    local listId = self.selectedManagerFrameList

    -- If nothing is selected, do nothing
    if not listId then
        return
    end

    -- Remove all entries from checklist frame
    self:RemoveListFromChecklistFrame(listId)

    -- Remove list from database
    table.remove(self.db.profile.lists, listId)

    -- Add default list if we deleted all others
    if table.getn(self.db.profile.lists) <= 0 then
        self.db.profile.lists[1] = {
            name = "Default",
            entries = {}
        }
        if self.db.profile.showListHeaders then
            self:UpdateListOnChecklistFrame(1)
        end
    end

    -- Reload list dropdown
    ToggleDropDownMenu(1, nil, self.checklistManagerListDropDown)

    CloseDropDownMenus()

    -- Reset dropdown selection
    UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, 1)
    self.selectedManagerFrameList = 1

    -- Reload list manager
    self:UpdateEntriesForScrollFrame()

    self:UpdateEntryPositionsOnChecklistFrame()
end

-- Removes the selected entry from the manager frame and database
function ListTracker:DeleteSelectedEntry(currentBox)

    -- If icon clicked get info
    if currentBox then
        local listId = currentBox.listId
        local entryId = currentBox.entryId

        self:RemoveEntryFromChecklistFrame(listId, entryId)

        table.remove(self.db.profile.lists[listId].entries, entryId)

        self:UpdateEntriesForScrollFrame()
        self:UpdateEntryPositionsOnChecklistFrame()
        return
    end

end

-- Moves the selected entry up in the options frame and database
function ListTracker:MoveSelectedEntryUp(currentBox)

    -- If icon clicked get info
    if currentBox then
        local listId = currentBox.listId
        local entryId = currentBox.entryId

        -- If the selected entry is already at the top of the list, do nothing
        if entryId <= 1 then
            return
        end

        -- Swap the selected entry and the one directly above
        local prevQuest = self.db.profile.lists[listId].entries[entryId - 1]
        self.db.profile.lists[listId].entries[entryId - 1] = self.db.profile.lists[listId].entries[entryId]
        self.db.profile.lists[listId].entries[entryId] = prevQuest

        if self.checklistFrame.lists[listId] then
            prevQuest = self.checklistFrame.lists[listId].entries[entryId - 1]
            self.checklistFrame.lists[listId].entries[entryId - 1] = self.checklistFrame.lists[listId].entries[entryId]
            self.checklistFrame.lists[listId].entries[entryId] = prevQuest
        end

        self:UpdateEntriesForScrollFrame()
        self:UpdateEntryPositionsOnChecklistFrame()

        self.checklistManagerFrameText[entryId - 1]:SetText(self.selectedEntryColor ..
                                                                self.checklistManagerFrameText[entryId - 1]:GetText())
        self.selectedManagerFrameText = entryId - 1
        return
    end
end

-- Moves the selected entry down in the options frame and database
function ListTracker:MoveSelectedEntryDown(currentBox)

    -- If icon clicked get info
    if currentBox then
        local listId = currentBox.listId
        local entryId = currentBox.entryId

        local tableSize = table.getn(self.db.profile.lists[listId].entries)

        -- If the selected entry is already at the bottom of the list, do nothing
        if entryId >= tableSize then
            return
        end

        -- Swap the selected entry and the one directly above
        local nextQuest = self.db.profile.lists[listId].entries[entryId + 1]
        self.db.profile.lists[listId].entries[entryId + 1] = self.db.profile.lists[listId].entries[entryId]
        self.db.profile.lists[listId].entries[entryId] = nextQuest

        if self.checklistFrame.lists[listId] then
            nextQuest = self.checklistFrame.lists[listId].entries[entryId + 1]
            self.checklistFrame.lists[listId].entries[entryId + 1] = self.checklistFrame.lists[listId].entries[entryId]
            self.checklistFrame.lists[listId].entries[entryId] = nextQuest
        end

        self:UpdateEntriesForScrollFrame()
        self:UpdateEntryPositionsOnChecklistFrame()

        self.checklistManagerFrameText[entryId + 1]:SetText(self.selectedEntryColor ..
                                                                self.checklistManagerFrameText[entryId + 1]:GetText())
        self.selectedManagerFrameText = entryId + 1
        return
    end
end

-- Resets the color of the previously selected options text
function ListTracker:ResetSelectedManagerFrameText()
    if self.selectedManagerFrameText then
        local text = self.checklistManagerFrameText[self.selectedManagerFrameText]:GetText()
        if string.find(text, self.selectedEntryColor) then
            self.checklistManagerFrameText[self.selectedManagerFrameText]:SetText(string.sub(text, 11))
        end
    end
    self.selectedManagerFrameText = nil
end

-- Create new list if it does not exist and update checklist frame
function ListTracker:CreateChecklistList()

    -- Grab text from edit box
    local newList = strtrim(self.checklistManagerListTextField:GetText())

    -- Discard if text was empty
    if newList == "" then
        return
    end

    -- Check if list exists already
    for listId, list in ipairs(self.db.profile.lists) do
        if list.name == newList then
            return
        end
    end

    -- Add new quest to database
    local tableSize = table.getn(self.db.profile.lists) + 1
    self.db.profile.lists[tableSize] = {}
    self.db.profile.lists[tableSize].name = newList
    self.db.profile.lists[tableSize].entries = {}
    self.db.profile.lists[tableSize].expanded = true

    -- Update selected list
    self.selectedManagerFrameList = tableSize

    ToggleDropDownMenu(1, nil, self.checklistManagerListDropDown)

    CloseDropDownMenus()

    UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, tableSize)

    -- Update scroll frame
    self:UpdateEntriesForScrollFrame()

    -- Update UI Checklist
    if self.db.profile.showListHeaders then
        self:UpdateListOnChecklistFrame(tableSize)
        -- Update positions because of visibility change
        self:UpdateEntryPositionsOnChecklistFrame()
    end

    -- Reset text for edit box
    self.checklistManagerListTextField:SetText("")
end

-- Create new entry if it does not exist and update checklist frame
function ListTracker:CreateChecklistEntry()

    if not self.selectedManagerFrameList then
        return
    end

    local listId = self.selectedManagerFrameList

    -- Grab text from edit box
    local newEntry = strtrim(self.checklistManagerTextField:GetText())

    -- Discard if text was empty
    if newEntry == "" then
        return
    end

    -- Keep track if we are creating a new entry or overwriting an old
    local overwrite = false

    -- Keep track of index of existing or new
    local index = 0

    -- Check if entry exists already, if so overwrite
    for entryId, entry in ipairs(self.db.profile.lists[listId].entries) do
        if entry.text == newEntry then
            overwrite = true
            index = entryId
            self.db.profile.lists[listId].entries[index] = self:CreateDatabaseEntry(newEntry)
            break
        end
    end

    if not overwrite then
        -- Add new entry to database
        index = table.getn(self.db.profile.lists[listId].entries) + 1
        self.db.profile.lists[listId].entries[index] = self:CreateDatabaseEntry(newEntry)
    end

    self.db.profile.lists[listId].completed = false
    if self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].checkbox then
        self.checklistFrame.lists[listId].checkbox:SetChecked(false)
    end

    -- Update scroll frame
    self:UpdateEntriesForScrollFrame()

    -- Update UI Checklist
    self:UpdateEntryOnChecklistFrame(listId, index, true)

    -- Update positions because of visibility change
    self:UpdateEntryPositionsOnChecklistFrame()

    -- Update visibility change
    self:UpdateVisibilityForListOnChecklistFrame(listId, self.db.profile.hideCompleted)

    -- Reset text for edit box
    self.checklistManagerTextField:SetText("")

    -- Reset checkboxes
    self.checklistManagerWeeklyCheckbox:SetChecked(false)
    self.checklistManagerManualCheckbox:SetChecked(false)
end

-- Creates a new list entry in the database using the current fields
function ListTracker:CreateDatabaseEntry(text)
    local noneChecked = true -- false Disabled for Options TODO

    local entry = {
        text = text,
        checked = true,
        completed = false,
        days = {
            [SUNDAY] = noneChecked or self.checklistManagerSundayCheckbox:GetChecked(),
            [MONDAY] = noneChecked or self.checklistManagerMondayCheckbox:GetChecked(),
            [TUESDAY] = noneChecked or self.checklistManagerTuesdayCheckbox:GetChecked(),
            [WEDNESDAY] = noneChecked or self.checklistManagerWednesdayCheckbox:GetChecked(),
            [THURSDAY] = noneChecked or self.checklistManagerThursdayCheckbox:GetChecked(),
            [FRIDAY] = noneChecked or self.checklistManagerFridayCheckbox:GetChecked(),
            [SATURDAY] = noneChecked or self.checklistManagerSaturdayCheckbox:GetChecked()
        },
        weekly = self.checklistManagerWeeklyCheckbox:GetChecked(),
        manual = self.checklistManagerManualCheckbox:GetChecked()
    }
    return entry
end

-- Change Shown database value
function ListTracker:ToggleChecklistManagerShownCheckbox(currentBox)
    self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].checked = currentBox:GetChecked()
    self:UpdateEntryOnChecklistFrame(currentBox.listId, currentBox.entryId, currentBox:GetChecked())
    -- Update positions because of visibility change
    self:UpdateEntryPositionsOnChecklistFrame()
end

-- Change Weekly database value
function ListTracker:ToggleChecklistManagerWeeklyCheckbox(currentBox)
    if currentBox:GetChecked() then
        self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].weekly = currentBox:GetChecked()
        self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].manual = not currentBox:GetChecked()
    else
        self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].weekly = currentBox:GetChecked()
    end
    -- Update positions because of visibility change
    self:UpdateEntryPositionsOnChecklistFrame()
    self:UpdateEntriesForScrollFrame()
end

-- Change Manual database value
function ListTracker:ToggleChecklistManagerManualCheckbox(currentBox)
    if currentBox:GetChecked() then
        self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].manual = currentBox:GetChecked()
        self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].weekly = not currentBox:GetChecked()
    else
        self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].manual = currentBox:GetChecked()
    end
    -- Update positions because of visibility change
    self:UpdateEntryPositionsOnChecklistFrame()
    self:UpdateEntriesForScrollFrame()
end

-- Change database values, images, and checklist positions
function ListTracker:ToggleChecklistFrameListExpand(currentExpand)
    local listId = currentExpand.listId
    local expanded = not self.db.profile.lists[listId].expanded
    self.db.profile.lists[listId].expanded = expanded

    if expanded then
        currentExpand:SetNormalTexture(contractNormalTexture)
        currentExpand:SetPushedTexture(contractPushedTexture)

        for entryId, entry in pairs(self.checklistFrame.lists[listId].entries) do
            if self.db.profile.lists[listId].entries[entryId].checked then
                entry.checkbox:Show()
                entry.headerText:Show()
            end
        end
    else
        currentExpand:SetNormalTexture(expandNormalTexture)
        currentExpand:SetPushedTexture(expandPushedTexture)

        for entryId, entry in pairs(self.checklistFrame.lists[listId].entries) do
            entry.checkbox:Hide()
            entry.headerText:Hide()
        end
    end
    self:UpdateEntryPositionsOnChecklistFrame()
end

-- Change database values
function ListTracker:ToggleChecklistFrameListCheckbox(currentBox)
    self.db.profile.lists[currentBox.listId].completed = currentBox:GetChecked()

    for entryId, entry in pairs(self.db.profile.lists[currentBox.listId].entries) do
        self.db.profile.lists[currentBox.listId].entries[entryId].completed = currentBox:GetChecked()
        if self.checklistFrame.lists[currentBox.listId].entries[entryId] then
            self.checklistFrame.lists[currentBox.listId].entries[entryId].checkbox:SetChecked(currentBox:GetChecked())
        end
    end

    if self.db.profile.hideCompleted then
        self:UpdateVisibilityForListOnChecklistFrame(currentBox.listId, self.db.profile.hideCompleted)
    end
    self:UpdateEntryPositionsOnChecklistFrame()
end

-- Change database values
function ListTracker:ToggleSingleChecklistFrameCheckbox(currentBox)
    self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].completed = currentBox:GetChecked()
    self:UpdateVisibilityForEntryOnChecklistFrame(currentBox.listId, currentBox.entryId, self.db.profile.hideCompleted)

    if currentBox:GetChecked() then
        local allChecked = true
        for _, entry in pairs(self.db.profile.lists[currentBox.listId].entries) do
            if not entry.completed and entry.checked then
                allChecked = false
            end
        end
        if allChecked then
            self.db.profile.lists[currentBox.listId].completed = true
            if self.checklistFrame.lists[currentBox.listId] then
                self.checklistFrame.lists[currentBox.listId].checkbox:SetChecked(true)
                if self.db.profile.hideCompleted then
                    self.checklistFrame.lists[currentBox.listId].expand:Hide()
                    self.checklistFrame.lists[currentBox.listId].checkbox:Hide()
                    self.checklistFrame.lists[currentBox.listId].headerText:Hide()
                end
            end
        end
    else
        if self.checklistFrame.lists[currentBox.listId] and
            self.checklistFrame.lists[currentBox.listId].checkbox:GetChecked() then
            self.db.profile.lists[currentBox.listId].completed = false
            self.checklistFrame.lists[currentBox.listId].checkbox:SetChecked(false)
            self.checklistFrame.lists[currentBox.listId].expand:Show()
            self.checklistFrame.lists[currentBox.listId].checkbox:Show()
            self.checklistFrame.lists[currentBox.listId].headerText:Show()
        end
    end
    self:UpdateEntryPositionsOnChecklistFrame()
end

-- Update entries in entries scroll frame when scroll bar moves
function ListTracker:UpdateEntriesForScrollFrame()

    -- Remove highlight from selected entry, if any
    self:ResetSelectedManagerFrameText()

    -- Save selected listId
    local listId = self.selectedManagerFrameList

    -- Save number of checkboxes used
    local numberOfRows = 1

    -- Save number of entries in entries
    local numberOfEntries = 0

    if listId and self.db.profile.lists and self.db.profile.lists[listId] then
        numberOfEntries = table.getn(self.db.profile.lists[listId].entries)
        for entryId, entry in ipairs(self.db.profile.lists[listId].entries) do
            if numberOfRows <= self.maxEntries then
                if entryId > self.checklistManagerFrameScroll.offset then
                    local checkbox = self.checklistManagerFrameShownCheckboxes[numberOfRows]
                    checkbox:SetChecked(entry.checked)
                    checkbox.entryId = entryId
                    checkbox.listId = listId
                    checkbox:Show()

                    local label = self.checklistManagerFrameText[numberOfRows]
                    label:SetText(entry.text)
                    label:Show()

                    local weeklyCheckbox = self.checklistManagerFrameWeeklyCheckboxes[numberOfRows]
                    weeklyCheckbox:SetChecked(entry.weekly)
                    weeklyCheckbox.entryId = entryId
                    weeklyCheckbox.listId = listId
                    weeklyCheckbox:Show()

                    local weeklyCheckbox = self.checklistManagerFrameManualCheckboxes[numberOfRows]
                    weeklyCheckbox:SetChecked(entry.manual)
                    weeklyCheckbox.entryId = entryId
                    weeklyCheckbox.listId = listId
                    weeklyCheckbox:Show()

                    local deleteIcon = self.checklistManagerFrameDeleteIcon[numberOfRows]
                    deleteIcon.entryId = entryId
                    deleteIcon.listId = listId
                    deleteIcon:Show()

                    local moveUpIcon = self.checklistManagerFrameMoveUpIcon[numberOfRows]
                    moveUpIcon.entryId = entryId
                    moveUpIcon.listId = listId
                    moveUpIcon:Show()

                    local moveDownIcon = self.checklistManagerFrameMoveDownIcon[numberOfRows]
                    moveDownIcon.entryId = entryId
                    moveDownIcon.listId = listId
                    moveDownIcon:Show()

                    numberOfRows = numberOfRows + 1
                end
            end
        end
    end

    for i = numberOfRows, self.maxEntries do
        self.checklistManagerFrameShownCheckboxes[i]:Hide()
        self.checklistManagerFrameText[i]:Hide()
        self.checklistManagerFrameWeeklyCheckboxes[i]:Hide()
        self.checklistManagerFrameManualCheckboxes[i]:Hide()
        self.checklistManagerFrameDeleteIcon[i]:Hide()
        self.checklistManagerFrameMoveUpIcon[i]:Hide()
        self.checklistManagerFrameMoveDownIcon[i]:Hide()
    end

    -- Execute scroll bar update 
    FauxScrollFrame_Update(self.checklistManagerFrameScroll, numberOfEntries, self.maxEntries, 20, nil, nil, nil, nil,
        nil, nil, true)
end

-- Called when profile changes, reloads options, list dropdown, manager, and checklist
function ListTracker:RefreshEverything()
    -- Reload list dropdown
    ToggleDropDownMenu(1, nil, self.checklistManagerListDropDown)

    CloseDropDownMenus()

    UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, 1)
    self.selectedManagerFrameList = 1

    -- Reload list manager
    self:UpdateEntriesForScrollFrame()

    -- Delete existing checklist frame elements, save ui elements
    self:RemoveChecklistFrameElements()

    -- Reconstruct checklist frame
    self:CreateChecklistFrameElements()

    -- Move checklist frame
    self.checklistFrame:SetPoint(self.db.profile.framePosition.anchor, nil, self.db.profile.framePosition.anchor,
        self.db.profile.framePosition.x, self.db.profile.framePosition.y - 16)
end

-- Called when minimap icon is clicked
function ListTracker:HandleIconClick(button)
    if button == "LeftButton" then
        self.db.profile.framePosition.hidden = not self.db.profile.framePosition.hidden
        ListTracker:UpdateVisibilityForChecklistFrame()
    elseif button == "RightButton" then
        -- Open options menu in interface->addon menu
        InterfaceOptionsFrame_OpenToCategory(self.checklistManagerFrame)
    end
end

-- Called when chat command is executed to hide the checklist frame
function ListTracker:HideChecklistFrame()
    self.db.profile.framePosition.hidden = true
    self.checklistFrame:Hide()
end

-- Called when chat command is executed to hide the checklist frame
function ListTracker:ShowChecklistFrame()
    self.db.profile.framePosition.hidden = false
    self.checklistFrame:Show()
end

function ListTracker:UpdateVisibilityForIcon(hidden)
    -- TODO
end

function ListTracker.ObjectiveTrackerFrameShow(...)
    if ListTracker.db.profile.hideObjectives then
        ListTracker:UpdateVisibilityForChecklistFrame()
    else
        ListTracker.ShowObjectivesWindow(ObjectiveTrackerFrame)
    end
end

function ListTracker:UpdateVisibilityForChecklistFrame()
    if self.db.profile.framePosition.hidden then
        self.checklistFrame:Hide()
    else
        self.checklistFrame:Show()
    end
    if self.db.profile.hideObjectives then
        if self.db.profile.framePosition.hidden then
            ListTracker.ShowObjectivesWindow(ObjectiveTrackerFrame)
        else
            ObjectiveTrackerFrame:Hide()
        end
    end
end

function ListTracker:UpdateVisibilityForEntryOnChecklistFrame(listId, entryId, hidden)
    local entry = self.db.profile.lists[listId].entries[entryId]
    if hidden then
        if self.checklistFrame.lists[listId].entries[entryId] then
            if entry.completed then
                self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
                self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
            else
                self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
                self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
            end
        end
    else
        if not self.checklistFrame.lists[listId].entries[entryId] then
            if entry.checked then
                self:CreateEntryInChecklistFrame(listId, entryId, 0)
            end
        else
            self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
            self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
        end
    end
end

function ListTracker:UpdateVisibilityForListOnChecklistFrame(listId, hidden)
    local list = self.db.profile.lists[listId]
    if hidden then
        if self.checklistFrame.lists[listId] then
            if self.checklistFrame.lists[listId].entries then
                for entryId, entry in pairs(list.entries) do
                    if self.checklistFrame.lists[listId].entries[entryId] then
                        if entry.completed then
                            self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
                            self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
                        else
                            self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
                            self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
                        end
                    end
                end
            end
            if self.checklistFrame.lists[listId].expand then
                if list.completed then
                    self.checklistFrame.lists[listId].expand:Hide()
                    self.checklistFrame.lists[listId].checkbox:Hide()
                    self.checklistFrame.lists[listId].headerText:Hide()
                else
                    self.checklistFrame.lists[listId].expand:Show()
                    self.checklistFrame.lists[listId].checkbox:Show()
                    self.checklistFrame.lists[listId].headerText:Show()
                end
            end
        end
    else
        if not self.checklistFrame.lists[listId] or not self.checklistFrame.lists[listId].entries then
            self:CreateListOnChecklistFrame(listId, 0)
        else
            for entryId, entry in pairs(list.entries) do
                if not self.checklistFrame.lists[listId].entries[entryId] then
                    if entry.checked and entry.days[self.currentDay] then
                        self:CreateEntryInChecklistFrame(listId, entryId, 0)

                        if not (entry.completed and self.db.profile.hideCompleted) then
                            self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
                            self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
                        end
                    end
                end
            end
            if self.checklistFrame.lists[listId].expand then
                self.checklistFrame.lists[listId].expand:Show()
                self.checklistFrame.lists[listId].checkbox:Show()
                self.checklistFrame.lists[listId].headerText:Show()
            end
        end
    end
end

function ListTracker:UpdateVisibilityOnChecklistFrame(hidden)
    for listId, _ in pairs(self.db.profile.lists) do
        self:UpdateVisibilityForListOnChecklistFrame(listId, hidden)
    end
end

function ListTracker:UpdateScale(value)
    self.checklistFrame:SetScale(value)
end
