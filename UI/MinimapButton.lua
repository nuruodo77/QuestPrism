QuestPrism.MinimapButton = {}
QuestPrism.WorldMapButton = {}

local LDB     = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

local LDB_NAME = "QuestPrism"
local ICON     = "Interface\\AddOns\\QuestPrism\\Textures\\icon"

-- Minimap button through LibDBIcon: drag, hiding, third-party button collectors
-- and the addon compartment menu are handled by the lib. Position stored in
-- QuestPrismCharDB.minimap.
local dataObject = LDB:NewDataObject(LDB_NAME, {
    type = "launcher",
    text = "QuestPrism",
    icon = ICON,
    OnClick = function(frame, btn)
        if btn == "RightButton" then
            QuestPrism.QuickMenu.Open(frame)
        else
            QuestPrism.Panel.Toggle()
        end
    end,
    OnTooltipShow = function(tooltip)
        QuestPrism.MinimapButton.FillTooltip(tooltip)
    end,
})

-- Shared by the minimap launcher and the world map button: title, click hints,
-- and the number of pins QuestPrism hides on the open world map when above zero.
-- The count belongs to the map that is open, so it is only shown while it is.
function QuestPrism.MinimapButton.FillTooltip(tooltip)
    tooltip:AddLine("QuestPrism")
    tooltip:AddLine(QuestPrism_L.TOOLTIP_LEFT_CLICK, 1, 1, 1)
    tooltip:AddLine(QuestPrism_L.TOOLTIP_RIGHT_CLICK, 1, 1, 1)
    local mapOpen = type(WorldMapFrame) == "table" and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
    local total = QuestPrism.WorldMap and QuestPrism.WorldMap.GetHiddenTotal and QuestPrism.WorldMap.GetHiddenTotal() or 0
    if mapOpen and total > 0 then
        tooltip:AddLine(string.format(QuestPrism_L.TOOLTIP_HIDDEN_ON_MAP, total), 0.7, 0.7, 0.7)
    end
end

function QuestPrism.MinimapButton.Initialize()
    local db = QuestPrismCharDB.minimap
    if not LDBIcon:IsRegistered(LDB_NAME) then
        LDBIcon:Register(LDB_NAME, dataObject, db)
    end
    if LDBIcon.IsButtonCompartmentAvailable and LDBIcon:IsButtonCompartmentAvailable() then
        LDBIcon:AddButtonToCompartment(LDB_NAME, ICON)
    end
end

function QuestPrism.MinimapButton.IsHidden()
    return QuestPrismCharDB.minimap and QuestPrismCharDB.minimap.hide == true
end

function QuestPrism.MinimapButton.SetHidden(hide)
    hide = hide and true or false
    QuestPrismCharDB.minimap.hide = hide
    if not LDBIcon:IsRegistered(LDB_NAME) then return end
    if hide then
        LDBIcon:Hide(LDB_NAME)
    else
        LDBIcon:Show(LDB_NAME)
    end
end

QuestPrismWorldMapButtonMixin = {}

function QuestPrismWorldMapButtonMixin:OnLoad()
    self:SetFrameLevel(self:GetParent():GetFrameLevel() + 100)
end

function QuestPrismWorldMapButtonMixin:OnClick(btn)
    if btn == "RightButton" then
        QuestPrism.QuickMenu.Open(self)
    else
        QuestPrism.Panel.Toggle(true) -- anchored to the map
    end
end

function QuestPrismWorldMapButtonMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    QuestPrism.MinimapButton.FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function QuestPrismWorldMapButtonMixin:Refresh()
end

-- Button on the world map, top right of the canvas, below Blizzard's tracking
-- buttons. If another addon provides the Krowi_WorldMapButtons library, register
-- with it to share its button stack; otherwise place the button ourselves.
-- (The library is not embedded: its license does not allow redistribution.)
local WORLD_MAP_BUTTON_OFFSET_Y = -70 -- below Blizzard's two buttons (tracking, pin)

function QuestPrism.WorldMapButton.Initialize()
    if not WorldMapFrame then return end
    local krowi = LibStub and LibStub("Krowi_WorldMapButtons-1.4", true)
    if krowi and type(krowi.Add) == "function" then
        local ok, button = pcall(krowi.Add, krowi, "QuestPrismWorldMapButtonTemplate", "Button")
        if ok and button then
            QuestPrism.WorldMapButton.frame = button
            return
        end
    end
    local button = CreateFrame("Button", "QuestPrismWorldMapButton", WorldMapFrame, "QuestPrismWorldMapButtonTemplate")
    local anchor = (type(WorldMapFrame.GetCanvasContainer) == "function" and WorldMapFrame:GetCanvasContainer()) or WorldMapFrame
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -4, WORLD_MAP_BUTTON_OFFSET_Y)
    QuestPrism.WorldMapButton.frame = button
end
