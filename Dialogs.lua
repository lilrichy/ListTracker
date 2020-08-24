-- Reload UI Confirmation Dialog box.
function ListTracker:ReloadUiDialog()
    StaticPopupDialogs["List Tracker Reload UI"] = {
        text = "Would you like to reload the UI for this option to take effect?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            ReloadUI();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    };

    StaticPopup_Show ("List Tracker Reload UI");
end

--TODO Create NEWS Dialog