-- Current-process renderer information and the native Video > Advanced
-- multicore selection. The former renderer module is not loaded.
local loaded, result = pcall(require, 'gmodrp_vulkan_info')
local api = istable(result) and result or gmodrp_vulkan_info
local moduleError = not loaded and tostring(result) or nil
local applying = false
local pendingRequest
local lastMenuError
local settings = {
    {'gmod_mcore_test', '1'},
    {'mat_queue_mode', '2'},
    {'cl_threaded_bone_setup', '1'},
    {'r_threaded_client_shadow_manager', '1'},
    {'r_threaded_renderables', '1'}
}

local function numeric(value)
    local number = isstring(value) and tonumber(value)
    return number and number == number and number ~= math.huge and number ~= -math.huge
end

local function readProfile()
    if not loaded or not istable(api) or not isfunction(api.read_multicore_profile)
        or not isfunction(api.save_multicore_profile) then
        return nil, 'Multicore profile storage unavailable'
    end
    local ok, profile = pcall(api.read_multicore_profile)
    if not ok or not istable(profile) then return nil, 'Could not read the multicore profile' end
    if profile.error and profile.error ~= '' then return nil, 'Multicore profile error: ' .. tostring(profile.error) end
    return profile
end

local function previousValues(profile)
    if not profile or not istable(profile.previous) then return nil end
    local values = {}
    for index = 1, #settings do
        local value = profile.previous[index]
        if not numeric(value) and not (index > 3 and value == 'unavailable') then return nil end
        values[index] = value
    end
    return values
end

local function actualValues()
    local values, missing, legacy = {}, {}, {}
    local enabled = true
    for index, setting in ipairs(settings) do
        local cv = GetConVar(setting[1])
        local value = cv and cv:GetString()
        if not numeric(value) then
            if index > 3 then
                values[index] = 'unavailable'
                legacy[#legacy + 1] = setting[1]
            else
                missing[#missing + 1] = setting[1]
                enabled = false
            end
        else
            values[index] = value
            if tonumber(value) ~= tonumber(setting[2]) then enabled = false end
        end
    end
    return values, missing, enabled, legacy
end

-- Preserve a producer snapshot before native Apply can replace mat_queue_mode
-- with its standard dropdown value. Tables returned by actualValues are owned.
local lastNativeValues = actualValues()

local function withLegacy(message, legacy)
    if #legacy == 0 then return message end
    return message .. '\nLegacy settings unavailable: ' .. table.concat(legacy, ', ')
end

local function setMulticoreStatus(message)
    print('[Multicore] ' .. message)
end

local function showActual()
    return actualValues()
end

local function verify(target, message, commandErrors)
    local values, missing, _, legacy = showActual()
    local rejected = {}
    for index, setting in ipairs(settings) do
        if numeric(values[index]) and numeric(target[index]) and tonumber(values[index]) ~= tonumber(target[index]) then
            rejected[#rejected + 1] = setting[1] .. '=' .. values[index]
        end
    end
    local problems = {}
    if #missing > 0 then problems[#problems + 1] = 'Unavailable: ' .. table.concat(missing, ', ') end
    if #rejected > 0 then problems[#problems + 1] = 'Rejected or locked: ' .. table.concat(rejected, ', ') end
    if #commandErrors > 0 then problems[#problems + 1] = 'Command failed: ' .. table.concat(commandErrors, ', ') end
    setMulticoreStatus(withLegacy(#problems > 0 and table.concat(problems, '\n') or message, legacy))
    applying = false
end

local function applyMulticore(enabled, startup, originalOverride)
    if applying then return end
    local profile, problem = readProfile()
    if not profile then setMulticoreStatus(problem); showActual(); return end
    local current, missing = actualValues()
    if #missing > 0 then
        setMulticoreStatus('Unavailable: ' .. table.concat(missing, ', '))
        showActual()
        return
    end
    local original = previousValues(profile)
    if not enabled and not original then
        setMulticoreStatus('No saved original settings to restore; current settings kept.')
        showActual()
        return
    end
    -- Do not replace the saved originals with already-enabled profile values.
    if enabled and profile.enabled and not original then
        setMulticoreStatus('Saved original settings are invalid; current settings kept.')
        showActual()
        return
    end
    if enabled and not profile.enabled then
        if originalOverride ~= nil then
            original = previousValues({previous = originalOverride})
        else
            original = current
        end
        if not original then
            setMulticoreStatus('Original settings snapshot is unavailable; profile not changed.')
            return
        end
    end
    if not startup then
        local ok, saved, why = pcall(api.save_multicore_profile, enabled,
            original[1], original[2], original[3], original[4], original[5])
        if not ok or not saved then
            setMulticoreStatus('Could not save multicore profile: ' .. tostring(why or saved))
            showActual()
            return
        end
    end
    local target = {}
    local errors = {}
    applying = true
    setMulticoreStatus(enabled and 'Applying multicore settings...' or 'Restoring saved settings...')
    for index, setting in ipairs(settings) do
        target[index] = enabled and (current[index] == 'unavailable' and 'unavailable' or setting[2]) or original[index]
        if target[index] ~= 'unavailable' and current[index] ~= 'unavailable' then
            local ok = pcall(RunConsoleCommand, setting[1], target[index])
            if not ok then errors[#errors + 1] = setting[1] end
        end
    end
    -- Console commands are queued. Confirm live values after execution rather
    -- than displaying a saved preference as if the engine accepted it.
    timer.Simple(0.5, function()
        verify(target, enabled and 'Active: supported settings verified.'
            or 'Saved original settings restored and verified.', errors)
    end)
end

local function observe()
    if not loaded or not istable(api) or not isfunction(api.status) then
        return {available = false, error = moduleError or 'Renderer information module unavailable'}
    end
    local ok, status = pcall(api.status)
    if not ok or not istable(status) then
        return {available = false, error = tostring(status or 'Renderer status unavailable')}
    end
    status.available = true
    return status
end

local function summary(status)
    if not status.available then return 'Renderer information unavailable' end
    if status.loaded then
        local version = isstring(status.version) and status.version ~= '' and (' ' .. status.version) or ''
        return 'Loaded: ' .. tostring(status.translator or 'DXVK') .. version
            .. (status.vulkanLoaded and ' | Vulkan runtime loaded' or ' | Vulkan runtime not detected')
    end
    return 'Loaded backend: ' .. tostring(status.backend or 'Unknown') .. ' | DXVK not detected'
end

local function details(status)
    local rows = {summary(status)}
    if status.available then
        rows[#rows + 1] = 'Backend: ' .. tostring(status.backend or 'Unknown')
        rows[#rows + 1] = 'D3D9 module: ' .. tostring(status.path or 'Not detected')
        if status.gpu then rows[#rows + 1] = 'GPU: ' .. tostring(status.gpu) end
        rows[#rows + 1] = 'This reports modules loaded in this game process.'
    elseif status.error then
        rows[#rows + 1] = status.error
    end
    return table.concat(rows, '\n')
end

local function refresh()
    local status = observe()
    -- Native resource labels use these tokens when the graphics dialog opens.
    if language and isfunction(language.Add) then
        language.Add('GmodRP_RendererLoaded', summary(status))
        language.Add('GmodRP_RendererAPI', 'API: ' .. tostring(status.backend or 'Unavailable'))
    end
    return status
end

-- Retire earlier development overlays on reload. No floating menu controls are
-- created; changes are requested only by the native dialog's Apply handler.
timer.Remove('GmodRPVulkanInfoAttach')
hook.Remove('Think', 'GmodRPVulkanInfoAttach')
if IsValid(GmodRPVulkanInfoLabel) then GmodRPVulkanInfoLabel:Remove() end
if IsValid(GmodRPVulkanInfoPanel) then GmodRPVulkanInfoPanel:Remove() end
GmodRPVulkanInfoLabel, GmodRPVulkanInfoPanel = nil, nil

timer.Simple(0, function()
    local _, missing, enabled, legacy = showActual()
    local profile, problem = readProfile()
    if not profile then
        setMulticoreStatus(problem)
    elseif profile.enabled then
        applyMulticore(true, true)
    elseif #missing > 0 then
        setMulticoreStatus('Unavailable: ' .. table.concat(missing, ', '))
    else
        setMulticoreStatus(withLegacy(enabled and 'Active: supported settings verified.' or 'Off: current engine settings shown.', legacy))
    end
end)

-- Poll consumes native Apply requests once. Keep a request while the preceding
-- queued console commands are being verified; Cancel produces no request.
timer.Create('GmodRPNativeMulticoreMenu', 0.2, 0, function()
    if not loaded or not istable(api) or not isfunction(api.poll_graphics_menu) then return end
    local current, _, enabled = actualValues()
    local ok, state = pcall(api.poll_graphics_menu, enabled)
    if not ok or not istable(state) then
        local message = 'Native graphics menu unavailable: ' .. tostring(state)
        if lastMenuError ~= message then print('[Multicore] ' .. message); lastMenuError = message end
        return
    end
    if state.error and state.error ~= '' then
        if lastMenuError ~= state.error then print('[Multicore] ' .. tostring(state.error)); lastMenuError = state.error end
    else
        lastMenuError = nil
    end
    if state.available and (state.request == 0 or state.request == 1) then
        pendingRequest = {enabled = state.request == 1, original = lastNativeValues}
    end
    if not applying and pendingRequest ~= nil then
        local request = pendingRequest
        pendingRequest = nil
        applyMulticore(request.enabled, false, request.original)
    elseif not applying then
        lastNativeValues = current
    end
end)

-- Register native graphics-dialog text before that dialog is constructed.
refresh()

concommand.Add('gmodrp_graphics_status', function()
    print('[Renderer] ' .. details(refresh()))
end)

concommand.Add('gmodrp_multicore', function(_, _, arguments)
    if arguments[1] == '1' then applyMulticore(true, false)
    elseif arguments[1] == '0' then applyMulticore(false, false)
    else
        local _, missing, active = showActual()
        print('[Multicore] ' .. (active and 'Active' or 'Off')
            .. (#missing > 0 and ('; unavailable: ' .. table.concat(missing, ', ')) or ''))
    end
end)

concommand.Add('gmodrp_graphics_info', function()
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Renderer information')
    frame:SetSize(math.min(640, ScrW() - 32), 230)
    frame:Center()
    local text = vgui.Create('DLabel', frame)
    text:Dock(FILL)
    text:DockMargin(12, 12, 12, 12)
    text:SetWrap(true)
    text:SetContentAlignment(7)
    text:SetText(details(refresh()))
    frame:MakePopup()
end)
