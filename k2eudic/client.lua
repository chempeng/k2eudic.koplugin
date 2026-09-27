-- SPDX-License-Identifier: GPL-3.0-or-later
local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local Text = require("k2eudic.text")
local TLS = require("k2eudic.tls")
local _ = require("k2eudic.i18n")

local Client = {}
local BASE = "https://api.frdic.com/api/open/v1/studylist/"

local function failure(code)
    if code == 401 then return _("Authorization is invalid or expired. Please enter your Eudic authorization again.") end
    if code == 403 or code == 429 then
        return _("Eudic denied access or received too many requests. Try again later (HTTP %s).", code)
    end
    if code == 400 then return _("Invalid request parameters. Fetch and select a notebook again (HTTP 400).") end
    if code == 404 then return _("API endpoint or notebook not found. Fetch the notebook list again (HTTP 404).") end
    if code and code >= 300 and code < 400 then return _("The API returned a redirect. The request was stopped. Check your plugin version.") end
    if code then return _("Eudic returned HTTP %s. Please try again later.", code) end
    return _("Network request failed. Check your connection, device clock, and HTTPS support.")
end

function Client.request(authorization, method, path, payload, expected_status)
    authorization = Text.authorization(authorization)
    if not authorization then return nil, _("Please set valid Eudic authorization first.") end
    local chunks = {}
    local request = {
        url = BASE .. path,
        method = method,
        redirect = false,
        create = TLS.create,
        headers = {
            ["authorization"] = authorization,
            ["accept"] = "application/json",
        },
    }
    if payload then
        local ok, body = pcall(json.encode, payload)
        if not ok then return nil, _("Could not encode the request data.") end
        request.headers["content-type"] = "application/json; charset=utf-8"
        request.headers["content-length"] = tostring(#body)
        request.source = ltn12.source.string(body)
    end
    -- Restore the caller's timeout values even if LuaSocket raises an error.
    local old_block, old_total = socketutil.block_timeout, socketutil.total_timeout
    socketutil:set_timeout(5, 15)
    local bytes = 0
    local sink = socketutil.table_sink(chunks)
    request.sink = function(chunk, err)
        bytes = bytes + (chunk and #chunk or 0)
        if bytes > 1024 * 1024 then return nil, "response too large" end
        return sink(chunk, err)
    end
    local ok, result, code = pcall(http.request, request)
    socketutil:set_timeout(old_block, old_total)
    code = tonumber(code)
    -- Never display raw transport errors or response bodies: they may echo credentials.
    if not ok or not result then return nil, failure(nil) end
    if code ~= expected_status then return nil, failure(code) end
    local decoded_ok, data = pcall(json.decode, table.concat(chunks))
    if not decoded_ok or type(data) ~= "table" then
        return nil, _("Eudic returned an unexpected data format. The result could not be confirmed.")
    end
    return data
end

function Client.categories(authorization)
    local response, err = Client.request(authorization, "GET", "category?language=en", nil, 200)
    if not response then return nil, err end
    if type(response.data) ~= "table" then return nil, _("Eudic did not return a notebook list.") end
    local categories = {}
    for key, item in pairs(response.data) do
        if type(key) ~= "number" or type(item) ~= "table"
            or type(item.id) ~= "string" or item.id == ""
            or type(item.name) ~= "string" or item.language ~= "en" then
            return nil, _("Unexpected notebook data format. Check the API version.")
        end
        categories[#categories + 1] = { id = item.id, name = item.name }
    end
    table.sort(categories, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    return categories
end

function Client.add(authorization, category_id, word)
    word = Text.word(word)
    if not word then return nil, _("Select a word or phrase (up to 200 bytes).") end
    if type(category_id) ~= "string" or category_id == "" then
        return nil, _("Please choose a target notebook first.")
    end
    local result, err = Client.request(authorization, "POST", "words", {
        language = "en", category_id = category_id, words = { word },
    }, 201)
    if not result then return nil, err end
    return true
end

return Client
