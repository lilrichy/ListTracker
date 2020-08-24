-- Scale Update based on slider value
function ListTracker:UpdateScale(value)
    self.checklistFrame:SetScale(value)
end

-- Called when mini map icon is hidden or shown
function ListTracker:UpdateVisibilityForIcon(hidden)
    self.icon:Refresh("ListTrackerDO", hidden)
end