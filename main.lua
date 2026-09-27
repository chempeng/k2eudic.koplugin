-- SPDX-License-Identifier: GPL-3.0-or-later
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Client = require("k2eudic.client")
local Text = require("k2eudic.text")
local _ = require("k2eudic.i18n")

local BUTTON_ID = "90_k2eudic_add"
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or "."
local K2Eudic = WidgetContainer:extend{
    name = "k2eudic",
    is_doc_only = false,
    version = "0.3.0",
}

function K2Eudic:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/k2eudic.lua")
    self.authorization = self.settings:readSetting("authorization", "")
    self.category_id = self.settings:readSetting("category_id")
    self.category_name = self.settings:readSetting("category_name")
    self.edit_before_add = self.settings:readSetting("edit_before_add", false)
    self.key_import_disabled = self.settings:readSetting("key_import_disabled", false)
    -- Import only when no saved authorization exists. Manual changes take priority.
    if not Text.authorization(self.authorization) and not self.key_import_disabled then
        self:importKey()
    end
    self.ui.menu:registerToMainMenu(self)
    if self.ui.highlight and self.ui.highlight.addToHighlightDialog then
        self.ui.highlight:addToHighlightDialog(BUTTON_ID, function(highlight)
            return {
                text = _("Add to Eudic vocabulary"),
                enabled = highlight.selected_text ~= nil,
                callback = function()
                    -- onClose clears selected_text, so copy it before closing the popup.
                    local word = highlight.selected_text and highlight.selected_text.text
                    highlight:onClose()
                    self:addSelection(word)
                end,
            }
        end)
    end
end

function K2Eudic:saveSettings()
    self.settings:saveSetting("authorization", self.authorization)
    self.settings:saveSetting("category_id", self.category_id)
    self.settings:saveSetting("category_name", self.category_name)
    self.settings:saveSetting("edit_before_add", self.edit_before_add)
    self.settings:saveSetting("key_import_disabled", self.key_import_disabled)
    self.settings:flush()
end

function K2Eudic:info(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function K2Eudic:setAuthorization(authorization)
    if authorization ~= self.authorization then
        -- A different token may identify a different account.
        self.category_id, self.category_name, self.last_failed = nil, nil, nil
    end
    self.authorization = authorization
    self:saveSettings()
end

function K2Eudic:importKey()
    local file = io.open((self.path or PLUGIN_DIR) .. "/KEY", "rb")
    if not file then
        return nil, _("Cannot read KEY. Place a plain text file named KEY (no extension) next to main.lua in the plugin folder.")
    end
    local value = file:read(8193)
    file:close()
    if not value or #value > 8192 then
        return nil, _("KEY is empty, unreadable, or too large. It must contain only one line of Eudic authorization.")
    end
    -- UTF-8 BOM and trailing CRLF are common when creating the file on Windows.
    value = value:gsub("^\239\187\191", "")
    local authorization = Text.authorization(value)
    if not authorization then
        return nil, _("Invalid KEY format. Use UTF-8 plain text with one line containing your NIS authorization or token.")
    end
    self.key_import_disabled = false
    self:setAuthorization(authorization)
    return true
end

function K2Eudic:input(title, value, password, callback)
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = value or "",
        text_type = password and "password" or nil,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local input = dialog:getInputText()
                if callback(input) ~= false then UIManager:close(dialog) end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function K2Eudic:editAuthorization(touchmenu)
    self:input(_("Eudic authorization (NIS … or token)"), self.authorization, true, function(value)
        local authorization = Text.authorization(value)
        if not authorization then
            self:info(_("Authorization must not be empty or contain line breaks or spaces within the token."))
            return false
        end
        self:setAuthorization(authorization)
        if touchmenu then touchmenu:updateItems() end
    end)
end

function K2Eudic:runRequest(label, authorization, task, done)
    if self.busy then self:info(_("A request is in progress. Please wait.")) return end
    NetworkMgr:runWhenConnected(function()
        if self.closed or authorization ~= self.authorization then return end
        if self.busy then return end
        if self.last_request and os.time() - self.last_request < 3 then
            self:info(_("Please wait 3 seconds before trying again."))
            return
        end
        self.busy = true
        local progress = InfoMessage:new{ text = label, dismissable = false }
        UIManager:show(progress)
        UIManager:forceRePaint()
        self.last_request = os.time()
        local ok, result, err = pcall(task)
        UIManager:close(progress)
        self.busy = false
        if not ok then result, err = nil, _("The request could not be processed. Check KOReader compatibility and try again.") end
        done(result, err)
    end)
end

function K2Eudic:chooseCategory(touchmenu)
    local authorization = Text.authorization(self.authorization)
    if not authorization then self:info(_("Please set your Eudic authorization first.")) return end
    self:runRequest(_("Fetching Eudic notebooks…"), authorization,
        function() return Client.categories(authorization) end,
        function(categories, err)
            if not categories then self:info(err) return end
            if #categories == 0 then
                self:info(_("No English notebooks found. Create one in Eudic, then fetch the list again."))
                return
            end
            local menu
            local items = {}
            for _, item in ipairs(categories) do
                local category = item
                items[#items + 1] = {
                    text = category.name .. " [" .. category.id .. "]",
                    callback = function()
                        self.category_id, self.category_name = category.id, category.name
                        self:saveSettings()
                        UIManager:close(menu)
                        if touchmenu then touchmenu:updateItems() end
                    end,
                }
            end
            menu = Menu:new{
                title = _("Choose an English notebook"), item_table = items,
                close_callback = function() UIManager:close(menu) end,
            }
            UIManager:show(menu)
        end)
end

function K2Eudic:addSelection(value)
    local word = Text.word(value)
    if not word then self:info(_("Select a word or phrase (up to 200 bytes), not a whole paragraph.")) return end
    if self.edit_before_add then
        self:input(_("Edit the word or phrase to add"), word, false, function(input)
            local edited = Text.word(input)
            if not edited then self:info(_("Enter a word or phrase (up to 200 bytes).")) return false end
            self:sendWord(edited)
        end)
    else
        self:sendWord(word)
    end
end

function K2Eudic:sendWord(word, retry)
    local authorization = Text.authorization(self.authorization)
    if not authorization or not self.category_id then
        self:info(_("Set your authorization and choose a target notebook in the Eudic vocabulary menu first."))
        return
    end
    local target = retry or { word = word, id = self.category_id, name = self.category_name }
    -- Keep the selected target stable if Wi-Fi is enabled after the tap.
    self:runRequest(_("Adding to Eudic vocabulary…"), authorization,
        function() return Client.add(authorization, target.id, target.word) end,
        function(result, err)
            if result then
                self.last_failed = nil
                self:info(_("Submitted: %s\nNotebook: %s\nEudic automatically skips existing words.",
                    target.word, target.name or target.id))
            else
                self.last_failed = target
                self:info(err .. "\n" .. _("The addition could not be confirmed. Retry from the plugin menu; the original notebook will be used."))
            end
        end)
end

function K2Eudic:addToMainMenu(menu_items)
    menu_items.k2eudic = {
        text = _("Eudic vocabulary"),
        sub_item_table = {
            { text_func = function()
                return _("Authorization: %s", Text.authorization(self.authorization) and _("Set") or _("Not set"))
            end, callback = function(menu) self:editAuthorization(menu) end },
            { text = _("Import authorization from KEY"), callback = function(menu)
                local ok, err = self:importKey()
                if ok then
                    if menu then menu:updateItems() end
                    self:info(_("Authorization imported from KEY. Check your target notebook. You can now delete KEY."))
                else
                    self:info(err)
                end
            end },
            { text_func = function()
                return _("Target notebook: %s", self.category_name or _("Not selected"))
            end, callback = function(menu) self:chooseCategory(menu) end },
            { text = _("Edit before adding"), checked_func = function() return self.edit_before_add end,
                callback = function()
                    self.edit_before_add = not self.edit_before_add
                    self:saveSettings()
                end },
            { text = _("Add a word manually…"), callback = function()
                self:input(_("Add an English word or phrase"), "", false, function(value)
                    local word = Text.word(value)
                    if not word then self:info(_("Enter a word or phrase (up to 200 bytes).")) return false end
                    self:sendWord(word)
                end)
            end },
            { text_func = function()
                local last = self.last_failed
                return last and _("Retry: %s to %s", last.word, last.name or last.id) or _("Retry last failed addition")
            end, enabled_func = function() return self.last_failed ~= nil end,
                callback = function()
                    if self.last_failed then self:sendWord(self.last_failed.word, self.last_failed) end
                end },
            { text = _("Clear saved authorization"), callback = function(menu)
                self.authorization = ""
                self.category_id, self.category_name, self.last_failed = nil, nil, nil
                -- An old KEY must not silently sign the user back in on restart.
                self.key_import_disabled = true
                self:saveSettings()
                -- Flush does not rotate backups written within the last minute.
                -- Remove only this plugin's credential backup explicitly.
                os.remove(DataStorage:getSettingsDir() .. "/k2eudic.lua.old")
                if menu then menu:updateItems() end
            end },
            { text = _("Usage"), callback = function()
                self:info(_("1. Get your personal authorization at my.eudic.net/OpenAPI/Authorization.\n")
                    .. _("2. Enter your authorization, then select Target notebook to fetch and choose a notebook online.\n")
                    .. _("3. Under Long-press on text, select Ask with popup dialog and uncheck Dictionary on single word selection.\n")
                    .. _("4. Long-press a word and tap Add to Eudic vocabulary. You can also keep dictionary lookup enabled and hold longer to show the menu.\n\n")
                    .. _("Alternatively, create KEY in the plugin folder with one line of authorization. It is imported automatically when no authorization is saved. Use Import authorization from KEY to replace saved authorization.\n\n")
                    .. _("Only selected text is added; word forms are not converted and context is not uploaded. Do not share KEY or settings/k2eudic.lua."))
            end },
        },
    }
end

function K2Eudic:onCloseWidget()
    self.closed = true
    if self.ui.highlight and self.ui.highlight.removeFromHighlightDialog then
        self.ui.highlight:removeFromHighlightDialog(BUTTON_ID)
    end
end

function K2Eudic:onCloseDocument()
    self:onCloseWidget()
end

return K2Eudic
