COLLECTME_NUM_ITEMS_TO_DISPLAY = 9;

COLLECTME_CRITTER = 1;
COLLECTME_MOUNT   = 2;

COLLECTME_VERSION = "1.0v";

local PotentialCompanionsTable = { };
local PotentialMountsTable = { }; 
local MissingItemsTable = { };
local ClickedScrollItem = "";
local nextCompanion = nil;
local is_entered = false;
local currentTab = COLLECTME_CRITTER;

CollectMeSavedVars = { IgnoredCompanionsTable = { }, IgnoredMountsTable = { }, RndCom = { }, Options = { preview = 1 }, };

function CollectMe_OnLoad()
    this:RegisterForDrag("LeftButton");
    this:RegisterEvent("ADDON_LOADED");
    this:RegisterEvent("PLAYER_ENTERING_WORLD");
    
    SLASH_MASTERMOUNT1 = "/mastermount";
    SLASH_MASTERMOUNT2 = "/mm";
    SlashCmdList["MASTERMOUNT"] = CollectMe_SlashHandler;
    
    COLLECTME_LIST_ITEM_HEIGHT = floor(CollectMeFrameScrollFrameButton1:GetHeight());
    tinsert(UISpecialFrames, CollectMeFrame:GetName());
    PanelTemplates_SetTab(CollectMeFrame, COLLECTME_CRITTER);
    getglobal("CollectMeFrameHeaderFrameText"):SetText("Master Mounts "..COLLECTME_VERSION);
end

function CollectMe_OnEvent(event)
    if(event == "ADDON_LOADED") then
        if(arg1 == "MasterMount") then
            hooksecurefunc("MoveForwardStart",CollectMe_SummonOnMoving);
            hooksecurefunc("MoveBackwardStart", CollectMe_SummonOnMoving)
            hooksecurefunc("TurnLeftStart", CollectMe_SummonOnMoving)
            hooksecurefunc("TurnRightStart", CollectMe_SummonOnMoving)
            hooksecurefunc("ToggleAutoRun",CollectMe_SummonOnMoving);
            if(CollectMeSavedVars.Options["button_hide"] ~= nil) then
                CollectMeButtonFrame:Hide();
            end
            if(is_entered == true) then
                CollectMe_NextCompanion();
            end
        end 
    end
    if(event == "PLAYER_ENTERING_WORLD") then
        CollectMe_NextCompanion();
        is_entered = true;
    end
end

function CollectMe_SummonOnMoving()
    if CollectMeSavedVars.Options == nil then
        CollectMeSavedVars.Options = { }
    end
    if CollectMeSavedVars.Options["disableonpvp"] == 1 then     
        if not IsMounted() and not IsStealthed() and not InCombatLockdown() then
            if CollectMeSavedVars.Options["moving"] ~= nil then
                local companionActive = CollectMe_checkActive()
                if not companionActive then
                    if nextCompanion == nil then
                        CollectMe_NextCompanion()
                        if nextCompanion ~= nil then
                            CallCompanion("CRITTER", nextCompanion)
                        end
                    else
                        CallCompanion("CRITTER", nextCompanion)
                    end
                    CollectMe_NextCompanion()
                end
            end
        elseif CollectMe_checkActive() and InCombatLockdown() then
            CollectMe_Dismisser()
        end
    end
end

function CollectMe_checkActive()
    for i=1, GetNumCompanions("CRITTER") do
        local _, _, _, _, issummoned = GetCompanionInfo("CRITTER", i);
        if(issummoned ~= nil) then
            return true;
        end
    end
    return false;
end

function CollectMe_NextCompanion()
    local summonableCompanions = { };
    local pointer = 1;
    for i=1, GetNumCompanions("CRITTER") do
        local creatureID = GetCompanionInfo("CRITTER", i);
        if(CollectMeSavedVars.RndCom[creatureID] ~= nil and CollectMeSavedVars.RndCom[creatureID] ~= 0) then
            for j=1, CollectMeSavedVars.RndCom[creatureID] do
                table.insert(summonableCompanions, pointer, i);
                pointer = pointer + 1;
            end
        end
    end
    if (pointer ~= 1) then
        local call = math.random(1, pointer-1);
        nextCompanion = summonableCompanions[call];
        
        local _, _, _, texture = GetCompanionInfo("CRITTER", nextCompanion);
    
        getglobal("CollectMeButtonFrame"):SetBackdrop({bgFile = texture, 
                                            edgeFile = "Interface/Tooltips/UI-Tooltip-Border", 
                                            tile = false, tileSize = 0, edgeSize = 16, 
                                            insets = { left = 4, right = 4, top = 4, bottom = 4 }});
    else
        CollectMeButtonFrame:Hide();
    end
end

function CollectMe_SkipCompanion()
    CollectMe_NextCompanion();
end

function CollectMe_SummonCompanion()
    CallCompanion("CRITTER", nextCompanion);
    CollectMe_NextCompanion();
end

function CollectMe_SlashHandler(msg)
    PanelTemplates_SetTab(CollectMeFrame, CollectMeFrame.selectedTab);
    CollectMe_Update(CollectMeFrame.selectedTab);
    if (msg == "options" or msg == "config") then
        InterfaceOptionsFrame_OpenToCategory(CollectMePanel);
    elseif (msg == "randomcompanion") then
        if (nextCompanion ~= nil) then
            CallCompanion("CRITTER", nextCompanion);
        end
        CollectMe_NextCompanion();
    else
        if (CollectMeFrame:IsVisible()) then
            CollectMeFrame:Hide();
        else
            CollectMeFrame:Show();
        end
    end
end

function CollectMe_Update(id)
    for k,v in pairs(MissingItemsTable) do
        MissingItemsTable[k] = nil;
    end

    local totalItems, totalKnownItems = 0, 0;

    if ( id == COLLECTME_CRITTER ) then
        totalItems, totalKnownItems = CollectMe_CompanionUpdate();
    elseif ( id == COLLECTME_MOUNT ) then
        totalItems, totalKnownItems = CollectMe_MountUpdate();
    end
    
    local knownItemPercentage = floor((totalKnownItems/totalItems)*100);
    CollectMeFrameStatusBar:SetValue(knownItemPercentage);
    CollectMeFrameStatusBarText:SetText(totalKnownItems.." / "..totalItems.." - "..knownItemPercentage.."%");

    if ( CollectMeFrame:IsVisible() ) then
        CollectMeScrollFrameUpdate();
    end
end

function CollectMe_CompanionUpdate()
    local totalKnownCompanions = 0
    local knownCompanionsTable = {}
    local name, icon
    local t = {}
    local ignoredCompanionsTable = {}
    local totalIgnoredCompanions = 0
    local totalDBCompanions = 0

    local searchText = MountFilterL:GetText():lower()


    for i = 1, GetNumCompanions("CRITTER") do
        local creatureID, creatureName, spellID, icon, active = GetCompanionInfo("CRITTER", i)
        local name, _, icon, _, _, _, _, _, _ = GetSpellInfo(spellID)
        totalKnownCompanions = totalKnownCompanions + 1
        knownCompanionsTable[spellID] = 1
        if CollectMeSavedVars.IgnoredCompanionsTable[name] then
            CollectMeSavedVars.IgnoredCompanionsTable[name] = nil
        end
    end

    for k, v in pairs(PotentialCompanionsTable) do
        totalDBCompanions = totalDBCompanions + 1
        if knownCompanionsTable[k] == nil then
            name, _, icon, _, _, _, _, _, _ = GetSpellInfo(k)
            if searchText == "" or name:lower():find(searchText) then
                t = {}
                t.itemID = v
                t.name = name
                t.icon = icon
                if CollectMeSavedVars.IgnoredCompanionsTable[name] then
                    totalIgnoredCompanions = totalIgnoredCompanions + 1
                    t.isIgnored = true
                    table.insert(ignoredCompanionsTable, t)
                else
                    table.insert(MissingItemsTable, t)
                end
            end
        end
    end

    local function processVendorCompanions(vendorCompanions, headerName)
        local VendorCompanionsTable = {}
        local totalVendorCompanions = 0
        for k, v in pairs(vendorCompanions) do
            totalVendorCompanions = totalVendorCompanions + 1
            name, _, icon, _, _, _, _, _, _ = GetSpellInfo(k)
            if searchText == "" or name:lower():find(searchText) then
                t = {}
                t.itemID = v
                t.name = name
                t.icon = icon
                table.insert(VendorCompanionsTable, t)
            end
        end

        if #VendorCompanionsTable > 0 then
            table.sort(VendorCompanionsTable, CollectMe_SortTableByName)
            t = {}
            t.name = headerName .. " (" .. #VendorCompanionsTable .. ")"
            t.isHeader = true
            t.isExpanded = false
            table.insert(MissingItemsTable, t)
            for _, v in pairs(VendorCompanionsTable) do
                table.insert(MissingItemsTable, v)
            end
        end
        return #VendorCompanionsTable
    end

    totalDBCompanions = totalDBCompanions + processVendorCompanions(GoldVendorCompanions, "Gold Vendor Companions")
    totalDBCompanions = totalDBCompanions + processVendorCompanions(LegendaryVendorCompanions, "Legendary Vendor Companions")
    totalDBCompanions = totalDBCompanions + processVendorCompanions(DonorVendorCompanions, "Donor Vendor Companions")
    totalDBCompanions = totalDBCompanions + processVendorCompanions(AnotherCompanions, "Overall Mounts")

    return totalDBCompanions, totalKnownCompanions;
end


local function OnMountClick(mountName)
    RunMacroText("/cast " .. mountName)
end

function CollectMe_MountUpdate()
    local totalKnownMounts = 0
    local knownMountsTable = {}
    local name, icon
    local t = {}
    local ignoredMountsTable = {}
    local totalIgnoredMounts = 0
    local totalDBMounts = 0

    local searchText = MountFilterL:GetText():lower()

    for i = 1, GetNumCompanions("MOUNT") do
        local creatureID, creatureName, spellID, icon, active = GetCompanionInfo("MOUNT", i)
        local name, _, icon, _, _, _, _, _, _ = GetSpellInfo(spellID)
        totalKnownMounts = totalKnownMounts + 1
        knownMountsTable[spellID] = i
        if CollectMeSavedVars.IgnoredMountsTable[name] then
            CollectMeSavedVars.IgnoredMountsTable[name] = nil
        end
    end

    for k, v in pairs(PotentialMountsTable) do
        totalDBMounts = totalDBMounts + 1
        if knownMountsTable[k] == nil then
            name, _, icon, _, _, _, _, _, _ = GetSpellInfo(k)
            if searchText == "" or name:lower():find(searchText) then
                t = {}
                t.itemID = v
                t.name = name
                t.icon = icon
                t.spellID = k
                if CollectMeSavedVars.IgnoredMountsTable[name] then
                    totalIgnoredMounts = totalIgnoredMounts + 1
                    t.isIgnored = true
                    table.insert(ignoredMountsTable, t)
                else
                    table.insert(MissingItemsTable, t)
                end
            end
        end
    end

    local function processVendorMounts(vendorMounts, headerName)
        local vendorMountsTable = {}
        local totalVendorMounts = 0
        for k, v in pairs(vendorMounts) do
            totalVendorMounts = totalVendorMounts + 1
            name, _, icon, _, _, _, _, _, _ = GetSpellInfo(k)
            if searchText == "" or name:lower():find(searchText) then
                t = {}
                t.itemID = v
                t.name = name
                t.icon = icon
                t.spellID = k
                table.insert(vendorMountsTable, t)
            end
        end

        if #vendorMountsTable > 0 then
            table.sort(vendorMountsTable, CollectMe_SortTableByName)
            t = {}
            t.name = headerName .. " (" .. #vendorMountsTable .. ")"
            t.isHeader = true
            t.isExpanded = false
            table.insert(MissingItemsTable, t)
            for _, v in pairs(vendorMountsTable) do
                table.insert(MissingItemsTable, v)
            end
        end
        return #vendorMountsTable
    end

    totalDBMounts = totalDBMounts + processVendorMounts(GoldVendorMounts, "Gold Vendor Mounts")
    totalDBMounts = totalDBMounts + processVendorMounts(LegendaryVendorMounts, "Legendary Vendor Mounts")
    totalDBMounts = totalDBMounts + processVendorMounts(DonorVendorMounts, "Donor Vendor Mounts")
    totalDBMounts = totalDBMounts + processVendorMounts(AnotherMounts, "Other Special Mounts")

    return totalDBMounts, totalKnownMounts
end

function CollectMeScrollFrameUpdate()
    local displayTable = {}
    for k, v in ipairs(MissingItemsTable) do
        table.insert(displayTable, k, v)
    end

    local index = 1
    while index <= #displayTable do
        if displayTable[index].isHeader and (not displayTable[index].isExpanded) then
            local i = index + 1
            while i <= #displayTable and (not displayTable[i].isHeader) do
                table.remove(displayTable, i)
            end
        end
        index = index + 1
    end

    local totalItemsToShow = #displayTable
    local button, buttonText, buttonIcon, header, headerText, buttonItemID

    for line = 1, COLLECTME_NUM_ITEMS_TO_DISPLAY do
        index = line + FauxScrollFrame_GetOffset(CollectMeFrameScrollFrame)
        button = _G["CollectMeFrameScrollFrameButton" .. line]
        buttonText = _G["CollectMeFrameScrollFrameButton" .. line .. "Text"]
        buttonIcon = _G["CollectMeFrameScrollFrameButton" .. line .. "Icon"]
        buttonItemID = _G["CollectMeFrameScrollFrameButton" .. line .. "ItemID"]
        header = _G["CollectMeFrameScrollFrameHeader" .. line]
        headerText = _G["CollectMeFrameScrollFrameHeader" .. line .. "Text"]

        if index <= totalItemsToShow then
            if displayTable[index].isHeader then
                button:Hide()
                headerText:SetText(displayTable[index].name)
                header:Show()

                if displayTable[index].isExpanded then
                    header:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                else
                    header:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                end
            else
                header:Hide()
                buttonText:SetText(displayTable[index].name)
                buttonItemID:SetText(displayTable[index].itemID)
                buttonIcon:SetNormalTexture(displayTable[index].icon)
                button:Show()

                -- Asignar montura al botón aquí
                local mount = displayTable[index]
                button.icon = mount.icon
                button.spellID = mount.spellID
                button:SetScript("OnClick", function()
                    OnMountClick(mount.name)
                end)

                if mount.name == ClickedScrollItem then
                    button:LockHighlight()
                else
                    button:UnlockHighlight()
                end
            end
        else
            button:Hide()
            header:Hide()
        end
    end
    FauxScrollFrame_Update(CollectMeFrameScrollFrame, totalItemsToShow, COLLECTME_NUM_ITEMS_TO_DISPLAY, COLLECTME_LIST_ITEM_HEIGHT)
end


function CollectMe_ScrollItemMouseOver(self)
    local itemName = getglobal(self:GetName().."Text"):GetText();
    local text = "No Info";
    local isCompanion = false;
    for k,v in pairs(CollectMeCompanionInfo) do
        cName = GetSpellInfo(k);
        if(cName == itemName) then
            text = v;
            isCompanion = true;
            break;
        end
    end
    
    if (isCompanion == false) then
        for k,v in pairs(CollectMeMountInfo) do
            cName = GetSpellInfo(k);
            if(cName == itemName) then
                text = v;
                break;
            end
        end
    end

    local formattedName = string.format("|cff862ec0%s|r", itemName)
    local fullText = string.format("%s\n\n\n\n|cffffff00%s|r", formattedName, text)
    
    CollectMeInfoFrameText:SetText(fullText);
    CollectMeInfoFrame:Show();
    CollectMeScrollFrameUpdate();
    CollectMe_ModelHandler(self);
end

function CollectMe_ModelHandler(self)
    if(CollectMeSavedVars.Options["preview"] ~= nil) then 
        local creatureID = getglobal(self:GetName().."ItemID"):GetText();
	    if (creatureID ~= nil) then
            CollectMeModel:Show();
            CollectMeModel:SetModel("Interface\\Buttons\\TalkToMeQuestion_Grey.mdx"); 
			CollectMeModel:RefreshUnit(); 
            CollectMeModel:SetCreature(creatureID);
            local rotationSpeed = 0.5
            CollectMeModel:SetScript("OnUpdate", function(self, elapsed)
                local currentFacing = self:GetFacing()
                local newFacing = currentFacing + (rotationSpeed * elapsed)
                self:SetFacing(newFacing)
            end)
        end
    end
end

function CollectMe_ScrollHeaderClicked(headerName)
    for k,v in ipairs(MissingItemsTable) do
        if ( v.isHeader and v.name == headerName ) then
            v.isExpanded = not (v.isExpanded);
            CollectMeScrollFrameUpdate();
            break;
        end
    end
end

function CollectMe_SortTableByName(a, b)
    return (a.name < b.name);
end

function CollectMe_OnDragStart()
	if(CollectMeSavedVars.Options["button_lock"] == nil) then
        this:StartMoving();
    end
end

function CollectMe_OnDragStop()
    if(CollectMeSavedVars.Options["button_lock"] == nil) then
	   this:StopMovingOrSizing();
	end
end

function CollectMe_Dismisser()
    DismissCompanion("CRITTER");
end