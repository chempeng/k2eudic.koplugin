-- SPDX-License-Identifier: GPL-3.0-or-later
local M = {}

function M.authorization(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value:upper() == "NIS" then return nil end
    value = value:gsub("^[Nn][Ii][Ss]%s+", "")
    if value == "" or value:find("[%s%c]") then return nil end
    return "NIS " .. value
end

function M.word(value)
    if type(value) ~= "string" then return nil end
    -- Keep case, apostrophes and hyphens: no stemming or sentence expansion.
    value = value:gsub("\194\160", " "):gsub("\194\173", "")
    value = value:gsub("[%s%c]+", " "):match("^%s*(.-)%s*$")
    if value == "" or #value > 200 then return nil end
    return value
end

return M
