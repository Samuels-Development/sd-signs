---@type table sd-signs config root (configs/config.lua).
local config = require 'configs.config'

---Tagged, colour-coded console output. Mirrors the helper used across the other sd-*
---resources so log lines look the same wherever you are reading them.
local log = {}

local COLOURS = {
    build = '^5',
    place = '^4',
    net   = '^6',
    warn  = '^3',
    err   = '^1',
}

local function emit(tag, msg, force)
    if not force and not config.Debug then return end
    print(('%s[sd-signs:%s]^7 %s'):format(COLOURS[tag] or '^7', tag, msg))
end

---Debug line, suppressed unless Config.Debug is on.
function log.debug(tag, msg, ...)
    emit(tag, select('#', ...) > 0 and msg:format(...) or msg, false)
end

---Always printed, regardless of Config.Debug.
function log.info(tag, msg, ...)
    emit(tag, select('#', ...) > 0 and msg:format(...) or msg, true)
end

function log.warn(msg, ...)
    emit('warn', select('#', ...) > 0 and msg:format(...) or msg, true)
end

function log.err(msg, ...)
    emit('err', select('#', ...) > 0 and msg:format(...) or msg, true)
end

return log
