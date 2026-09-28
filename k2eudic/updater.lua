-- SPDX-License-Identifier: GPL-3.0-or-later
local http = require("socket.http")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local socketutil = require("socketutil")
local TLS = require("k2eudic.tls")
local _ = require("k2eudic.i18n")

local Updater = {
    API_URL = "https://api.github.com/repos/chempeng/k2eudic.koplugin/releases/latest",
    RELEASE_PREFIX = "https://github.com/chempeng/k2eudic.koplugin/releases/download/",
    MAX_DOWNLOAD = 5 * 1024 * 1024,
    MAX_EXTRACTED = 16 * 1024 * 1024,
}
local hosts = {
    ["api.github.com"] = true,
    ["github.com"] = true,
    ["release-assets.githubusercontent.com"] = true,
    ["objects.githubusercontent.com"] = true,
}

function Updater.compareVersions(a, b)
    local function parts(v)
        if type(v) ~= "string" then return end
        local x, y, z = v:match("^v?(%d+)%.(%d+)%.(%d+)$")
        if x then return { tonumber(x), tonumber(y), tonumber(z) } end
    end
    a, b = parts(a), parts(b)
    if not a or not b then return end
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] > b[i] and 1 or -1 end
    end
    return 0
end

-- No Eudic credentials are passed to GitHub, including across redirects.
function Updater.get(url, limit)
    for hop = 1, 4 do
        local host = type(url) == "string" and url:match("^https://([^/]+)/")
        if not hosts[host] then return nil, _("The update URL is not allowed.") end
        local chunks, received = {}, 0
        local old_block, old_total = socketutil.block_timeout, socketutil.total_timeout
        socketutil:set_timeout(10, 45)
        local ok, result, code, headers = pcall(http.request, {
            url = url, method = "GET", redirect = false, create = TLS.creator(host),
            headers = { ["User-Agent"] = "K2Eudic-Updater", ["Accept"] = "application/vnd.github+json" },
            sink = function(chunk)
                if chunk then
                    received = received + #chunk
                    if received > limit then return nil, "response too large" end
                    chunks[#chunks + 1] = chunk
                end
                return 1
            end,
        })
        socketutil:set_timeout(old_block, old_total)
        if not ok or not result then
            return nil, _("Could not download the update. Check your connection, device clock, and access to GitHub.")
        end
        code = tonumber(code)
        if code == 200 then return table.concat(chunks) end
        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
            url = headers and headers.location
        else
            return nil, _("GitHub returned HTTP %s. Please try again later.", tostring(code or "?"))
        end
    end
    return nil, _("Too many redirects while downloading the update.")
end

function Updater.parseRelease(data)
    if type(data) ~= "table" or data.draft or data.prerelease then
        return nil, _("Invalid GitHub release information.")
    end
    local version = type(data.tag_name) == "string" and data.tag_name:match("^v?(%d+%.%d+%.%d+)$")
    if not version or type(data.assets) ~= "table" then
        return nil, _("Invalid GitHub release information.")
    end
    local name = "k2eudic-" .. version .. ".zip"
    for __, asset in ipairs(data.assets) do
        if type(asset) == "table" and asset.name == name then
            local digest = type(asset.digest) == "string" and asset.digest:match("^sha256:([a-fA-F0-9]+)$")
            local expected_url = Updater.RELEASE_PREFIX .. data.tag_name .. "/" .. name
            if asset.browser_download_url ~= expected_url or not digest or #digest ~= 64
                or type(asset.size) ~= "number" or asset.size <= 0 or asset.size > Updater.MAX_DOWNLOAD then
                return nil, _("The release package or its SHA-256 checksum is missing or invalid.")
            end
            return { version = version, url = expected_url, digest = digest:lower(), size = asset.size }
        end
    end
    return nil, _("The release package or its SHA-256 checksum is missing or invalid.")
end

function Updater.fetchRelease()
    local body, err = Updater.get(Updater.API_URL, 1024 * 1024)
    if not body then return nil, err end
    local ok, data = pcall(json.decode, body)
    if not ok then return nil, _("Invalid GitHub release information.") end
    return Updater.parseRelease(data)
end

local function removeTree(path)
    local mode = lfs.symlinkattributes(path, "mode")
    if not mode then return true end
    if mode == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." and not removeTree(path .. "/" .. name) then return nil end
        end
        return lfs.rmdir(path)
    end
    return os.remove(path)
end

local function write(path, data)
    local file = io.open(path, "wb")
    if not file then return end
    local ok = file:write(data)
    local closed = file:close()
    return ok and closed
end

local function read(path, limit)
    local file = io.open(path, "rb")
    if not file then return end
    local data = file:read(limit + 1)
    file:close()
    if data and #data <= limit then return data end
end

local function safePath(path)
    if type(path) ~= "string" or path:find("[%c\\:]") or path:find("//", 1, true)
        or not path:match("^k2eudic%.koplugin/") then return false end
    for segment in path:gmatch("[^/]+") do
        if segment == "." or segment == ".." then return false end
    end
    local relative = path:sub(#"k2eudic.koplugin/" + 1)
    -- Settings and personal authorization must never come from a release archive.
    return relative ~= "KEY" and not relative:match("^KEY%.")
        and relative ~= "lic" and relative ~= "k2eudic.lua" and not relative:match("^settings/")
end

local function unpackRelease(archive, stage, version)
    local reader = require("ffi/archiver").Reader:new()
    if not reader:open(archive) then reader:close(); return nil end
    local ok = pcall(function()
        local total, count, seen = 0, 0, {}
        for entry in reader:iterate() do
            count = count + 1
            local path, size = entry.path, tonumber(entry.size)
            assert(safePath(path) and not seen[path] and count <= 200)
            assert(entry.mode == "file" or entry.mode == "directory")
            assert(size and size >= 0 and size <= 4 * 1024 * 1024)
            total = total + size
            assert(total <= Updater.MAX_EXTRACTED)
            seen[path] = true
            local destination = stage .. "/" .. path
            if entry.mode == "directory" then
                assert(require("util").makePath(destination))
            else
                assert(require("util").makePath(destination:match("^(.+)/[^/]+$")))
                -- Extract bytes, never archive-owned links or permissions.
                local content = assert(reader:extractToMemory(path))
                assert(write(destination, content))
                if path:match("%.lua$") then assert(loadfile(destination)) end
            end
        end
        assert(not reader.err)
        local prefix = "k2eudic.koplugin/"
        local required = { "main.lua", "_meta.lua", "k2eudic/client.lua", "k2eudic/text.lua",
            "k2eudic/tls.lua", "k2eudic/i18n.lua", "certs/cacert.pem" }
        if Updater.compareVersions(version, "0.3.1") >= 0 then
            required[#required + 1] = "k2eudic/updater.lua"
            required[#required + 1] = "k2eudic/updateui.lua"
        end
        for _, file in ipairs(required) do
            assert(lfs.attributes(stage .. "/" .. prefix .. file, "mode") == "file")
        end
        local main = assert(read(stage .. "/" .. prefix .. "main.lua", 1024 * 1024))
        assert(main:match('version%s*=%s*"([%d%.]+)"') == version)
    end)
    reader:close()
    return ok
end

-- Preparation does not modify the installed plugin and may run in a subprocess.
function Updater.prepare(plugin_dir, release)
    if lfs.symlinkattributes(plugin_dir, "mode") ~= "directory" then
        return nil, _("The plugin folder is not writable or is a symbolic link.")
    end
    local stage = plugin_dir .. ".update"
    if not removeTree(stage) or not lfs.mkdir(stage) then
        return nil, _("Could not create the update folder. Check free space and permissions.")
    end
    local function fail(err) removeTree(stage); return nil, err end
    local body, err = Updater.get(release.url, Updater.MAX_DOWNLOAD)
    if not body then return fail(err) end
    if #body ~= release.size or require("ffi/sha2").sha256(body) ~= release.digest then
        return fail(_("Update verification failed. The installed plugin has not been changed."))
    end
    local archive = stage .. "/release.zip"
    if not write(archive, body) or not unpackRelease(archive, stage, release.version) then
        return fail(_("Invalid update package, or insufficient free space. The installed plugin has not been changed."))
    end
    os.remove(archive)
    return true
end

-- Run the short directory swap in the parent, after the download has completed.
-- KOReader settings live outside plugin_dir and are never moved or overwritten.
function Updater.activate(plugin_dir)
    local stage, backup = plugin_dir .. ".update", plugin_dir .. ".backup"
    local staged = stage .. "/k2eudic.koplugin"
    if lfs.symlinkattributes(staged, "mode") ~= "directory" then
        return nil, _("The prepared update is missing. Please check for updates again.")
    end
    if lfs.symlinkattributes(plugin_dir .. "/KEY") then
        local key = read(plugin_dir .. "/KEY", 8192)
        if not key or not write(staged .. "/KEY", key) then
            return nil, _("Could not preserve KEY. The installed plugin has not been changed.")
        end
    end
    if not removeTree(backup) or not os.rename(plugin_dir, backup) then
        return nil, _("Could not back up the plugin. The installed plugin has not been changed.")
    end
    if not os.rename(staged, plugin_dir) then
        if not os.rename(backup, plugin_dir) then
            return nil, _("Update activation failed. Restore the plugin from the adjacent .backup folder; your KOReader settings are intact.")
        end
        return nil, _("Update activation failed. The previous plugin was restored.")
    end
    removeTree(stage)
    return true
end

return Updater
