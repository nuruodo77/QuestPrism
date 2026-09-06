QuestPrism.Widgets = {}

-- Shared widget construction, so the settings window and the map tab cannot drift
-- apart. Only what both need lives here.

-- Push buttons use the game's modern three-slice atlas art
-- (SharedButtonSmallTemplate, from the 128-RedButton atlas, natural height 28)
-- rather than the legacy Interface\Buttons\UI-Panel-Button textures.
-- ThreeSliceButtonMixin is declared by the same file as those templates, so its
-- absence means a client that only has the old panel button: fall back to it
-- instead of failing to build the frame at all.
local MODERN_TEMPLATE, MODERN_HEIGHT = "SharedButtonSmallTemplate", 28
local LEGACY_TEMPLATE, LEGACY_HEIGHT = "UIPanelButtonTemplate", 22

local template, height

function QuestPrism.Widgets.ButtonTemplate()
    if not template then
        if type(ThreeSliceButtonMixin) == "table" then
            template, height = MODERN_TEMPLATE, MODERN_HEIGHT
        else
            template, height = LEGACY_TEMPLATE, LEGACY_HEIGHT
        end
    end
    return template, height
end

-- The caller sets its own points and tooltip; the height is the art's own, so the
-- three slices never scale.
function QuestPrism.Widgets.Button(parent, text, width, onClick)
    local buttonTemplate, buttonHeight = QuestPrism.Widgets.ButtonTemplate()
    local btn = CreateFrame("Button", nil, parent, buttonTemplate)
    btn:SetSize(width, buttonHeight)
    btn:SetText(text)
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end
