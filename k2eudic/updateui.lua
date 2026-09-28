-- SPDX-License-Identifier: GPL-3.0-or-later
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Updater = require("k2eudic.updater")
local _ = require("k2eudic.i18n")

local UpdateUI = {}
UpdateUI.__index = UpdateUI

function UpdateUI:new(plugin)
    return setmetatable({ plugin = plugin }, self)
end

function UpdateUI:run(label, task, done)
    local plugin = self.plugin
    if plugin.busy or plugin.closed then return end
    plugin.busy = true
    Trapper:wrap(function()
        local progress = InfoMessage:new{ text = label, dismissable = false }
        UIManager:show(progress)
        UIManager:forceRePaint()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ok, value, err = pcall(task)
            if not ok then return { error = _("Could not process the update. Please try again after restarting KOReader.") } end
            return { value = value, error = err }
        end, progress)
        UIManager:close(progress)
        plugin.busy = false
        if plugin.closed then return end
        done(completed and result or { error = _("The update was interrupted. Please try again.") })
    end)
end

function UpdateUI:showRelease(release)
    local plugin = self.plugin
    if Updater.compareVersions(release.version, plugin.version) ~= 1 then
        plugin:info(_("K2Eudic is up to date (v%s).", plugin.version), 3)
        return
    end
    UIManager:show(ConfirmBox:new{
        text = _("Update K2Eudic from v%s to v%s?\n\nYour authorization and target notebook will be kept. Restart KOReader after installation.", plugin.version, release.version),
        ok_text = _("Download and install"),
        cancel_text = _("Cancel"),
        ok_callback = function() self:install(release) end,
    })
end

function UpdateUI:check(manual, touchmenu)
    local plugin = self.plugin
    local function check()
        if plugin.closed or plugin.busy or self.checking or self.installed then return end
        plugin.settings:saveSetting("last_update_check", os.time())
        plugin.settings:flush()
        if not manual then
            -- A silent read-only check; never enable Wi-Fi just to check updates.
            self.checking = true
            Trapper:wrap(function()
                local completed, result = Trapper:dismissableRunInSubprocess(function()
                    local ok, release = pcall(Updater.fetchRelease)
                    return ok and release or false
                end, false)
                self.checking = false
                if completed and result and not plugin.closed then self.release = result end
            end)
            return
        end
        self:run(_("Checking for updates…"), Updater.fetchRelease, function(result)
            if not result.value then plugin:info(result.error) return end
            self.release = result.value
            if touchmenu then touchmenu:updateItems() end
            self:showRelease(self.release)
        end)
    end
    if manual then
        NetworkMgr:runWhenConnected(check)
    elseif NetworkMgr:isConnected() then
        check()
    end
end

function UpdateUI:install(release)
    local plugin = self.plugin
    if self.installed then return end
    NetworkMgr:runWhenConnected(function()
        -- Flush any pending user settings before replacing the code directory.
        plugin:saveSettings()
        self:run(_("Downloading and verifying the update…"), function()
            return Updater.prepare(plugin.path, release)
        end, function(result)
            if not result.value then self.release = nil; plugin:info(result.error) return end
            local ok, err = Updater.activate(plugin.path)
            if not ok then plugin:info(err) return end
            self.installed = true
            UIManager:show(ConfirmBox:new{
                text = _("Update installed. Your authorization and notebook are preserved. Restart KOReader to apply it."),
                ok_text = _("Restart now"), cancel_text = _("Later"),
                ok_callback = function() UIManager:restartKOReader() end,
            })
        end)
    end)
end

function UpdateUI:menu()
    local plugin = self.plugin
    return {
        { text = _("Current version: v%s", plugin.version), enabled = false },
        { text_func = function()
            if self.installed then return _("Restart KOReader to finish updating") end
            if self.release and Updater.compareVersions(self.release.version, plugin.version) == 1 then
                return _("Update available: v%s", self.release.version)
            end
            return _("Check for updates")
        end, callback = function(menu)
            if self.installed then
                UIManager:show(ConfirmBox:new{
                    text = _("Restart KOReader to finish updating"),
                    ok_text = _("Restart now"), cancel_text = _("Later"),
                    ok_callback = function() UIManager:restartKOReader() end,
                })
            elseif self.release and Updater.compareVersions(self.release.version, plugin.version) == 1 then
                self:showRelease(self.release)
            else
                self:check(true, menu)
            end
        end },
        { text = _("Automatically check daily"),
            checked_func = function() return plugin.settings:readSetting("auto_update_check", true) end,
            callback = function()
                local enabled = not plugin.settings:readSetting("auto_update_check", true)
                plugin.settings:saveSetting("auto_update_check", enabled)
                plugin.settings:flush()
                self:cancelAutoCheck()
                if enabled then self:scheduleAutoCheck() end
            end },
    }
end

function UpdateUI:cancelAutoCheck()
    if self.auto_task then UIManager:unschedule(self.auto_task); self.auto_task = nil end
end

function UpdateUI:scheduleAutoCheck()
    local settings = self.plugin.settings
    if not settings:readSetting("auto_update_check", true) then return end
    local last = tonumber(settings:readSetting("last_update_check")) or 0
    if os.time() - last < 24 * 60 * 60 and os.time() >= last then return end
    self.auto_task = function()
        self.auto_task = nil
        if not self.plugin.closed then self:check(false) end
    end
    UIManager:scheduleIn(5, self.auto_task)
end

return UpdateUI
