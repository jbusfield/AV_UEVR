local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local configui = require("libs/configui")
local reticule = require("libs/reticule")
local hands = require('libs/hands')
local attachments = require('libs/attachments')
local input = require('libs/input')
local pawnModule = require('libs/pawn')
local animation = require('libs/animation')
local montage = require('libs/montage')
local interaction = require('libs/interaction')
local ui = require('libs/ui')
local remap = require('libs/remap')
local gestures = require('libs/gestures')

--uevrUtils.setDeveloperMode(true)

ui.init()
montage.init()
interaction.init()
attachments.init()
attachments.setGripUpdateTimeout(200)
reticule.init()
pawnModule.init()
remap.init()
input.init()

attachments.allowChildVisibilityHandling(false)

local versionTxt = "v1.0.0"
local title = "Avowed First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "Avowed Config",
		saveFile = "avowed_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200},}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "UI" }, { widgetType = "begin_rect", },
				expandArray(ui.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Input" }, { widgetType = "begin_rect", },
				expandArray(input.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
				{
					widgetType = "checkbox",
					id = "full_body_mode",
					label = "Full Body Mode (experimental)",
					initialValue = true
				},
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Settings" }, { widgetType = "begin_rect", },
				{
					widgetType = "checkbox",
					id = "enable_lumen",
					label = "Enable Lumen",
					initialValue = true
				},
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		}
	}
}
configui.create(configDefinition)

local status = {}

local function isFullBodyMode()
    if pawn ~= nil then
       return not pawn:BP_GetIsFirstPerson()
    end
end

--Courtesy of markmon
local function toggle_lumen(enabled)
    set_cvar_int("r.Lumen.DiffuseIndirect.Allow", enabled)
    if enabled == 1 then
        set_cvar_float("r.TonemapperGamma", 0.0)
    else
        set_cvar_float("r.TonemapperGamma", 1.5)
    end
end

configui.onCreateOrUpdate("full_body_mode", function(value)
    if pawn ~= nil then
        local isFP = pawn:BP_GetIsFirstPerson()
        if isFP == value then
            uevr.api:get_player_controller(0):ToggleIsFirstPerson()
        end
    end
end)

configui.onCreateOrUpdate("enable_lumen", function(value)
    toggle_lumen(value and 1 or 0)
end)

--some of the montages try to take over the camera which causes a flickering in the left eye.  This compensates for that behavior
local yawMontages = {AM_UNI_1P_PullUp_32_In2Crouch = 1200, AM_1P_SingleDoor_Unbar = 3000, AM_1P_WallLever_Up = 3000, AM_1P_WallLever_Down = 3000, AM_UNI_1P_PushUp20_In2Crouch = 1000, AM_Uni_Container_Medium_Open = 3500, AM_Uni_DoubleDoor_Open_F = 1500, AM_Uni_DoubleDoor_Open_B = 1500, AM_1P_OpenSingleDoor_L = 1500, AM_1P_OpenSingleDoor_R = 1000,AM_Container_Large_Wide_Open = 4000, AM_Container_Large_Default_Open = 4000, AM_UNI_1P_Parkour_Mantle_120 = 700, AM_UNI_1P_Parkour_Mantle_315 = 1200, AM_UNI_1P_Parkour_Vault_200 = 1000, AM_UNI_1P_Parkour_Vault_300 = 1000}
function on_montage_change(montageObject, montageName)
    if status["activeYawMontage"] ~= nil then
        delay(500, function()
            --dont disable the previous one if a new one has started
            if status["activeYawMontage"] == nil then
                input.setPawnRotationMode(isFullBodyMode() and input.PawnRotationMode.SIMPLE or input.PawnRotationMode.LOCKED)
                input.setOptimizeBodyYawCalculations(true)
            end
        end)
        status["activeYawMontage"] = nil
    elseif yawMontages[montageName] ~= nil then
        input.setPawnRotationMode(input.PawnRotationMode.RIGHT_CONTROLLER) --dont allow montage body changes to affect head rotation
        input.setOptimizeBodyYawCalculations(false) --dont let the right controller affect head rotation
        status["activeYawMontage"] = montageName
    end
end

local function onIsClimbingLadderChange(isClimbing)
    if isClimbing then
        if isFullBodyMode() then
            input.setPawnRotationMode(input.PawnRotationMode.GAME)
            input.setOptimizeBodyYawCalculations(false)
        else
            input.setDisabled(true)
        end
    else
        delay(500, function()
            if isFullBodyMode() then
                input.setPawnRotationMode(isFullBodyMode() and input.PawnRotationMode.SIMPLE or input.PawnRotationMode.LOCKED)
                input.setOptimizeBodyYawCalculations(true)
            else
                input.setDisabled(false)
            end
        end)
    end
end

local function getChildFromSkeletalMeshName(parent, name)
	if uevrUtils.validate_object(parent) ~= nil and name ~= nil then
		local children = parent.AttachChildren
		if children ~= nil then
			for i, child in ipairs(children) do
				if child.SkeletalMesh ~= nil and string.find(child.SkeletalMesh:get_full_name(), name) then
					return child
				end
			end
		end
	end
	return nil
end

local function getChildrenFromSkeletalMeshName(parent, name)
    local result = {}
	if uevrUtils.validate_object(parent) ~= nil and name ~= nil then
		local children = parent.AttachChildren
		if children ~= nil then
			for i, child in ipairs(children) do
				if child.SkeletalMesh ~= nil and string.find(child.SkeletalMesh:get_full_name(), name) then
					table.insert(result, child)
				end
			end
		end
	end
	return result
end

-- A single glove can have many glove meshes. 
-- For example, Vambraces have 3 separate meshes, one for nude hands and two for the bracers themselves.
-- This structure keeps track of the different glove meshes and returns the correct one when requested.
local handMeshes = {
    initialized = false,
    meshes = {},
	init = function(self, parent)
        local foundMeshes = getChildrenFromSkeletalMeshName(parent, "GLOVES")
        --look for one with "Nude/" in the name first. If that exists make it the hands mesh and remove it
        --from the list. Then assign the others to glove2Mesh and glove3Mesh if they exist.
        --If no nude mesh is found, then assign the first to handsMesh, second to glove2Mesh, third to glove3Mesh.
        for i, mesh in ipairs(foundMeshes) do
            if string.find(mesh.SkeletalMesh:get_full_name(), "Nude/") then
                self.meshes["Arms"] = mesh
                table.remove(foundMeshes, i)
                break
            end
        end
        if self.meshes["Arms"] == nil and #foundMeshes >= 1 then
            self.meshes["Arms"] = foundMeshes[1]
            table.remove(foundMeshes, 1)
        end
        if #foundMeshes >= 1 then
            self.meshes["Gloves2"] = foundMeshes[1]
            table.remove(foundMeshes, 1)
        end
        if #foundMeshes >= 1 then
            self.meshes["Gloves3"] = foundMeshes[1]
            table.remove(foundMeshes, 1)
        end
    end,
	get = function(self, parent, name) -- "Arms" or "Gloves2" or "Gloves3"
        if self.initialized == false then
            self:init(parent)
            self.initialized = true
        end
        return self.meshes[name]
    end,
    reset = function(self)
        self.initialized = false
        self.meshes = {}
    end,
}

function getCustomHandComponent(key)
    local meshName = isFullBodyMode() and "Mesh" or "FirstPersonSkelMesh"
    --print("Getting custom hand component for key: " .. tostring(key))
    if key == "ForeArms" then
        return getChildFromSkeletalMeshName(uevrUtils.getValid(pawn,{"FirstPersonSkelMesh"}), "TORSO") --Pawn.FirstPersonSkelMesh(PoseableMeshComponent_2147479490)
    else
        return handMeshes:get(uevrUtils.getValid(pawn,{meshName}), key)
    end
end

--return true if arm bones should be hidden
pawnModule.registerIsArmBonesHiddenCallback(function()
    local hideArmBones = nil
    if uevrUtils.getValid(pawn) ~= nil and pawn:IsSwimming() or status["isClimbingLadder"] then
        hideArmBones = false
    end
	return hideArmBones, 0
end)

--return true if hands should be hidden, second param is priority
hands.registerIsHiddenCallback(function()
    local hideHands = nil
    if uevrUtils.getValid(pawn) ~= nil and pawn:IsSwimming() or status["isClimbingLadder"] then
        hideHands = true
    end
	return hideHands, 0
end)

local function getWeaponMesh(slot)
    if uevrUtils.getValid(pawn) == nil then
        return nil, nil
    end
    local weapon = pawn:GetEquippedActorFromSlotInActiveLoadout(uevrUtils.tagFromString(slot))
    if weapon == nil or weapon:IsUnsheathed() == false then
        return nil, nil
    end

    return weapon and weapon:GetBaseMesh(), weapon
end


attachments.registerOnGripUpdateCallback(function()
    if uevrUtils.isInCutscene() then return end

    local currentWeaponRight, currentWeaponActorRight = getWeaponMesh("EquipSlot.RightHand")
    local currentWeaponLeft, currentWeaponActorLeft = getWeaponMesh("EquipSlot.LeftHand")

    --if its a bow then make left the primary hand
    if currentWeaponRight and string.find(currentWeaponRight:get_full_name(), "2H_Bow")  then
        currentWeaponLeft = currentWeaponRight
        currentWeaponRight = nil
    end

    status["currentWeaponRight"] = currentWeaponRight
    status["currentWeaponLeft"] = currentWeaponLeft
    status["currentWeaponActorRight"] = currentWeaponActorRight
    status["currentWeaponActorLeft"] = currentWeaponActorLeft

    if hands.getHandComponent(Handed.Right, "Arms") == nil or hands.getHandComponent(Handed.Left, "Arms") == nil then
        return
    end
    return currentWeaponRight, hands.getHandComponent(Handed.Right, "Arms"), nil, currentWeaponLeft, hands.getHandComponent(Handed.Left, "Arms"), nil, true, true
 end)

local function setDefaultTargeting(handed, offset)
	if handed == Handed.Left then
		input.setAimMethod(input.AimMethod.LEFT_CONTROLLER)
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.LEFT_CONTROLLER)
	else
		input.setAimMethod(input.AimMethod.RIGHT_CONTROLLER)
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.RIGHT_CONTROLLER)
	end
end

local function setMeleeOffset(hand)
    local offset = attachments.getActiveAttachmentMeleeRotationOffset(hand)
    if offset then
        input.setAimRotationOffset(offset)
        --if you use controller based reticule targetting the set this as well
        reticule.setTargetRotationOffset(offset)
        uevrUtils.updateDeferral("melee_attack")
    end
end

--won't callback unless an updateDeferral hasnt been called in the last 1000ms
uevrUtils.createDeferral("melee_attack", 1000, function()
    input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
    reticule.setTargetRotationOffset()
end)

local function getNiagaraChildren(parent)
    local result = {}
	if uevrUtils.validate_object(parent) ~= nil  then
		local children = parent.AttachChildren
		if children ~= nil then
			for i, child in ipairs(children) do
				if child:is_a(uevrUtils.get_class("Class /Script/Niagara.NiagaraComponent")) then
					table.insert(result, child)
				end
			end
		end
	end
	return result
end

--this is used for grimoire spells
local currentNiagaraChildren = {}
setInterval(100, function()
    local meshName = isFullBodyMode() and "Mesh" or "FirstPersonSkelMesh"
    local niagaraChildren = getNiagaraChildren(uevrUtils.getValid(pawn,{meshName}))
    --print("Found " .. #niagaraChildren .. " niagara children attached to hand mesh.")
    --add any new niagara components to attachments and remove any that existed before but are now gone
    for i, child in ipairs(niagaraChildren) do
        local found = false
        for j, existingChild in ipairs(currentNiagaraChildren) do
            if existingChild == child then
                found = true
                break
            end
        end
        if not found then
            setDefaultTargeting(Handed.Right) --grimoire spells fire from the right hand
            attachments.attachToMesh(child, controllers.getController(Handed.Right))
        end
    end
    currentNiagaraChildren = niagaraChildren
end)


setInterval(1000, function()
    --check if the pawns hands mesh and if so, destroy our so they will regenrate with the new mesh
    local meshName = isFullBodyMode() and "Mesh" or "FirstPersonSkelMesh"
    local newHandMesh = getChildFromSkeletalMeshName(uevrUtils.getValid(pawn,{meshName}), "GLOVES")
    if status["currentHandMesh"] ~= newHandMesh then
        status["currentHandMesh"] = newHandMesh
        --print("Hand mesh changed, destroying existing hands and resetting.")
        handMeshes:reset()
        hands.destroyHands()
    end

    if status["currentWeaponLeft"] == nil and status["currentWeaponRight"] == nil then
        reticule.setActiveReticuleByLabel("Unarmed Reticule")
    else
        --reticule.setActiveReticuleByLabel("Weapon Reticule")
    end
end)

local function hideThirdPersonHead(value)
    local children = uevrUtils.getValid(pawn, {"Mesh", "AttachChildren"})
    if children ~= nil then
---@diagnostic disable-next-line: param-type-mismatch
        for i, child in ipairs(children) do
            if child.SkeletalMesh ~= nil then
                local meshName = child.SkeletalMesh:get_full_name()
                if string.find(meshName, "HEAD/HUMAN") or string.find(meshName, "HEAD/GODLIKE") or string.find(meshName, "HEAD/HAIR") or string.find(meshName, "HEAD/FACIALHAIR") then
                    child:SetRenderInMainPass(not value)
                    child:SetRenderInDepthPass(not value)
                    --child:SetVisibility(not value, false)
                    --child:SetHiddenInGame(value, false)
                end
             end
        end
    end
end

local function handleFullBody()
    if uevrUtils.getValid(pawn) ~= nil then
        local isInCutscene = uevrUtils.isInCutscene()
        local isFP = pawn:BP_GetIsFirstPerson()
        --print("Is full body = ", not isFP)
        configui.setValue("full_body_mode", not isFP, true)
        hideThirdPersonHead(not isFP and not isInCutscene)
        pawnModule.setCurrentProfileByLabel(isFP and "Default" or "Full Body")
        input.setCurrentProfileByLabel(isFP and "Default" or "Full Body")
        if not isFP then
            pawnModule.hideArmsBones(not isInCutscene)
        end
    else --if the pawn isnt ready then keep trying until it is
        delay(1000, function()
            handleFullBody()
        end)
    end
end

function on_cutscene_change(value)
    handleFullBody()
end

attachments.registerAttachmentChangeCallback(function(id, hand, attachment)
	-- Reduces processing when no melee weapon is equipped
    local isRightMelee = attachments.isActiveAttachmentMelee(Handed.Right)
    local isLeftMelee = attachments.isActiveAttachmentMelee(Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isLeftMelee, Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isLeftMelee, Handed.Left)

    reticule.setActiveReticuleByLabel("Weapon Reticule", true)

    -- Courtesy of markmon
    -- weapon hits react faster improving user feedback
    local newSpeed = 10.0
    local weapon = hand == Handed.Right and status["currentWeaponActorRight"] or status["currentWeaponActorLeft"]
    if weapon ~= nil and attachments.isActiveAttachmentMelee(hand) and uevrUtils.getValid(weapon, {"AttackAttributeSet","AttackSpeedMult"}) ~= nil and weapon.AttackAttributeSet.AttackSpeedMult.BaseValue ~= nil and weapon.AttackAttributeSet.AttackSpeedMult.CurrentValue ~= nil then
        weapon.AttackAttributeSet.AttackSpeedMult.BaseValue = newSpeed
        weapon.AttackAttributeSet.AttackSpeedMult.CurrentValue = newSpeed
    end

    --Fix shield Z fighting
    if string.find(id, "Shield") then
      if attachment.AttachChildren ~= nil and #attachment.AttachChildren > 0 then
            for i, child in ipairs(attachment.AttachChildren) do
                if child:is_a(uevrUtils.get_class("Class /Script/Engine.StaticMeshComponent")) then
                    child:SetHiddenInGame(false, false)
                    child:SetVisibility(true, false)
                    child.RelativeScale3D = uevrUtils.vector(0.990, 0.990, 0.990)
                end
            end
        end
    end
end)


gestures.registerSwipeRightCallback(function(strength, hand)
	--print("Swipe Right detected for right hand")
    if hand == Handed.Right then
    	status["hasSwipeRight"] = true
        setDefaultTargeting(Handed.Right)
        setMeleeOffset(Handed.Right)
    else
        status["hasSwipeLeft"] = true
        setDefaultTargeting(Handed.Left)
        setMeleeOffset(Handed.Left)
    end
end, true, true)

gestures.registerSwipeLeftCallback(function(strength, hand)
	--print("Swipe Left detected for right hand")
    if hand == Handed.Right then
    	status["hasSwipeRight"] = true
        setDefaultTargeting(Handed.Right)
        setMeleeOffset(Handed.Right)
    else
        status["hasSwipeLeft"] = true
        setDefaultTargeting(Handed.Left)
        setMeleeOffset(Handed.Left)
    end
end, true, true)

--wont callback unless an uevrUtils.updateDeferral("is_blocking") hasnt been called in the last 1000ms
uevrUtils.createDeferral("is_blocking", 1000, function()
    status["leftHandIsBlocking"] = false
end)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)

    if uevrUtils.isButtonPressed(state,XINPUT_GAMEPAD_X) then
        setDefaultTargeting(Handed.RIGHT)
    elseif state.Gamepad.bRightTrigger > 0 and status["currentWeaponLeft"] ~= nil and string.find(status["currentWeaponLeft"]:get_full_name(), "2H_Bow") then
        setDefaultTargeting(Handed.Left)
    else
        --used to stop left hand from targettting when blocking
        if uevrUtils.getValid(pawn) ~= nil then
            if pawn:IsAttemptingToBlock() then
                status["leftHandIsBlocking"] = true
                uevrUtils.updateDeferral("is_blocking")
            end
        end

        if state.Gamepad.bRightTrigger > 0 or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER) then
            setDefaultTargeting(Handed.Right)
        elseif status["leftHandIsBlocking"] ~= true and state.Gamepad.bLeftTrigger > 0 or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER) then
            setDefaultTargeting(Handed.Left)
        end
    end

    if status["hasSwipeRight"] then
        --print("Processing right swipe gesture into input")
        state.Gamepad.bRightTrigger = 255
        status["hasSwipeRight"] = false
    end
	if status["hasSwipeLeft"] then
        --print("Processing left swipe gesture into input")
        state.Gamepad.bRightTrigger = 255
        status["hasSwipeLeft"] = false
    end

end, 5) --increased priority to get values before remap occurs

uevrUtils.registerLevelChangeCallback(function()

    hook_function("BlueprintGeneratedClass /Game/Blueprints/Characters/Player/BPC_AlabamaPlayer.BPC_AlabamaPlayer_C", "BP_OnFirstPersonChanged", false, nil,
		function(fn, obj, locals, result)
            handleFullBody()
		end
	, true)

    handleFullBody()
    handMeshes:reset()
end)

--Custom  method of getting top level UI widgets since WidgetBlueprintLibrary:GetAllWidgetsOfClass doesnt do the job in this game
--I dont like polling for objects, even every second, but hooking the native functions that are required
--to do it the right way, simply doesn't work. Native functions lock up the whole game after a level change.
--The number of objects returned is small, < 20 usually, so performance impact should be minimal.
local screenWidgets = {}
setInterval(1000, function()
    local widgets = uevrUtils.find_all_instances("Class /Script/UiSystem.ScreenWidget", false)
    local currentWidgets = {}

    if widgets ~= nil then
        -- Build a map of currently found widgets with their shown state
        pcall(function()
            for i, widget in ipairs(widgets) do
                local widgetKey = tostring(widget) --keys look like sol.uevr::API::UObject*: 00000233A4B9FEA8
                local isShown = widget:IsShown()
                currentWidgets[widgetKey] = {widget = widget, isShown = isShown}

                -- Check if this is a new widget or state changed
                local previousState = screenWidgets[widgetKey]
                if previousState == nil or previousState.isShown ~= isShown then
                    -- State changed - update viewport accordingly
                    if isShown then
                        ui.addViewportWidget(widget)
                    else
                        ui.removeViewportWidget(widget)
                    end
                end
            end

            -- Check for removed widgets and clean up
            for widgetKey, widgetData in pairs(screenWidgets) do
                if currentWidgets[widgetKey] == nil then
                    -- Widget was removed - remove from viewport if it was shown
                    if widgetData.isShown then
                        ui.removeViewportWidget(widgetData.widget)
                    end
                end
            end
		end)

        -- Update the tracked widgets
        screenWidgets = currentWidgets
    end
end)

local function getBoundsChildrenFromSkeletalMesh(parent)
    local result = {}
	if uevrUtils.validate_object(parent) ~= nil then
		local children = parent.AttachChildren
		if children ~= nil then
			for i, child in ipairs(children) do
				if child:is_a(uevrUtils.get_class("Class /Script/Alabama.BoundsComponent")) then
					table.insert(result, child)
				end
			end
		end
	end
	return result
end

setInterval(200, function()
    --set 2d mode during level changes so the ui has a nice black background
    local currentMatchState = uevrUtils.getMatchState()
    if currentMatchState ~= status["matchState"] then
        status["matchState"] = currentMatchState
        uevrUtils.set_2D_mode(currentMatchState ~= "InProgress")
    end

    if uevrUtils.getValid(pawn) ~= nil then
         if status["isClimbingLadder"] ~= pawn.bUseClimbingAnimations then
            status["isClimbingLadder"] = pawn.bUseClimbingAnimations
            onIsClimbingLadderChange(pawn.bUseClimbingAnimations == true)
        end
    end
end)

setInterval(1000, function()
    --hide secondary holstered weapons
    if uevrUtils.getValid(pawn) ~= nil then
        local children = getBoundsChildrenFromSkeletalMesh(uevrUtils.getValid(pawn, {"FirstPersonSkelMesh"}))
        if children then
            for i, child in ipairs(children) do
                --print("Bounds Component:", child.AttachSocketName)
                if string.find(child.AttachSocketName:to_string(), "holster") and child.AttachChildren ~= nil then
                    for j, grandChild in ipairs(child.AttachChildren) do
                        --print("  Child Component:", grandChild:get_full_name())
                        if (grandChild:is_a(uevrUtils.get_class("Class /Script/Engine.StaticMeshComponent")) or grandChild:is_a(uevrUtils.get_class("Class /Script/Engine.SkeletalMeshComponent"))) and not string.find(grandChild:get_full_name(), "UtilityRigMesh") then
                            --print("     Its hidden")
                            grandChild:SetHiddenInGame(true, true)
                            grandChild:SetVisibility(false, true)
                        end
                    end
                end
            end
        end
    end

end)
