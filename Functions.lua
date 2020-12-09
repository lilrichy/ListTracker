-- Scale Update based on slider value
function ListTracker:UpdateScale(value)
    self.checklistFrame:SetScale(value)
end

-- Called when mini map icon is hidden or shown
function ListTracker:UpdateVisibilityForIcon(hidden)
    self.icon:Refresh("ListTrackerDO", hidden)
end

-- Reset List Manually
function ListTracker:ResetLists()
    for listId, list in ipairs(self.db.profile.lists) do
        for entryId, entry in ipairs(list.entries) do
            if not entry.manual then
                entry.completed = false
                if self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].entries[entryId] and
                    self.checklistFrame.lists[listId].entries[entryId].checkbox then
                    self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(false)
                end
                currentListReset = true
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

    -- Check if list should be set to show for reset
    if self.db.profile.showReset and self.db.profile.framePosition.hidden then
        ListTracker:ShowChecklistFrame()
    end

end