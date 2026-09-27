-- SPDX-License-Identifier: GPL-3.0-or-later
local https = require("ssl.https")
local M = {}
local source = debug.getinfo(1, "S").source
local directory = assert(source:match("^@(.*/)[^/]+$"))

function M.matchesCertificate(cert)
    if not cert then return false end
    local extensions = cert:extensions()
    local san = extensions and extensions["2.5.29.17"]
    local names = san and san.dNSName
    if type(names) ~= "table" then return false end
    -- Only one fixed API host is supported. No CN fallback or partial wildcards.
    for _, name in ipairs(names) do
        if type(name) == "string" then
            name = name:lower()
            if name == "api.frdic.com" or name == "*.frdic.com" then return true end
        end
    end
    return false
end

function M.create()
    local connection = https.tcp{
        verify = "peer",
        cafile = directory .. "../certs/cacert.pem",
        protocol = "any",
        options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1", "no_tlsv1_1" },
    }()
    -- LuaSec installs forwarded methods only after a successful handshake.
    -- LuaSocket also calls close() when connect() fails before that point.
    connection.close = function(self)
        return self.sock:close()
    end
    local connect = connection.connect
    connection.connect = function(self, host, port)
        if host ~= "api.frdic.com" or tonumber(port) ~= 443 then
            return nil, "unexpected TLS endpoint"
        end
        -- LuaSec checks the certificate chain during the handshake. LuaSec 1.3.2
        -- does not check hostnames, so check SAN before LuaSocket sends headers.
        local ok, result = pcall(connect, self, host, port)
        local valid, matches = pcall(function()
            return M.matchesCertificate(self.sock:getpeercertificate())
        end)
        if not ok or not result or not valid or not matches then
            pcall(function() self.sock:close() end)
            return nil, "TLS verification failed"
        end
        return 1
    end
    return connection
end

return M
