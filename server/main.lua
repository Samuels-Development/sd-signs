---@type table sd-signs config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared/log.lua): tagged, colour-coded prints.
local log    = require 'shared.log'
---@type table Sign geometry + validation (shared/sign.lua).
local Sign   = require 'shared.sign'

---@type table<number, table> signId -> record (authoritative, mirrored to clients)
local signs = {}
---@type number highest id issued so far this session
local nextId = 0

---Whether a player may build, edit or remove signs. Config.Ace = false opens it to
---everyone, which is not recommended: signs are persistent, visible to every player
---and cost entity budget.
---@param src number|string player server id
---@return boolean
local function allowed(src)
    if not config.Ace then return true end
    return IsPlayerAceAllowed(src, config.Ace)
end

---Let the client ask whether it may build/review, so the commands can say "no
---permission" instead of opening a menu whose submit silently gets dropped.
lib.callback.register('sd-signs:isAllowed', function(src)
    return allowed(src)
end)

---How many signs one licence already owns, for the per-player cap.
---@param licence string
---@return integer
local function ownedBy(licence)
    local n = 0
    for _, rec in pairs(signs) do
        if rec.owner == licence then n = n + 1 end
    end
    return n
end

---Ownership key for a player. Falls back to the session id when a licence is not
---available, so a sign is always attributable to something.
---@param src number|string player server id
---@return string
local function licenceOf(src)
    return GetPlayerIdentifierByType(src, 'license') or ('src:' .. src)
end

---Rows -> in-memory records. Kept separate from the wire shape so the client never
---has to know about column names.
local function load()
    if not config.Persist then return end
    -- Inside CreateThread so MySQL.query.await has a coroutine to yield on. Called
    -- from a plain callback it would never resume, and persistence would silently
    -- load nothing.
    CreateThread(function()
        -- The resource used to be called sd-alphabet, and its table sd_alphabet_signs.
        -- Carry the rows over before CREATE TABLE runs, or that would cheerfully make
        -- an empty sd_signs and every placed sign would look deleted while still
        -- sitting in the old table.
        local existing = MySQL.query.await([[
            SELECT TABLE_NAME FROM information_schema.TABLES
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME IN ('sd_alphabet_signs', 'sd_signs')
        ]]) or {}
        local present = {}
        for _, row in ipairs(existing) do present[row.TABLE_NAME] = true end
        if present.sd_alphabet_signs and not present.sd_signs then
            MySQL.query.await('RENAME TABLE `sd_alphabet_signs` TO `sd_signs`')
            log.info('net', 'migrated sd_alphabet_signs -> sd_signs')
        end

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `sd_signs` (
                `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `owner`     VARCHAR(64)  NOT NULL,
                -- Wide enough for maxRows * maxLength plus separators, so a fresh
                -- install never has to run the widening ALTER below.
                `text`      VARCHAR(192) NOT NULL,
                `colour`    VARCHAR(16)  NOT NULL,
                `colours`   VARCHAR(64)  NULL,
                `style`     VARCHAR(16)  NULL,
                `anim`      VARCHAR(16)  NULL,
                `animspeed` FLOAT        NULL,
                `spin`      FLOAT        NULL,
                `size`      FLOAT        NOT NULL,
                `thickness` FLOAT        NOT NULL,
                `tracking`  FLOAT        NOT NULL,
                `x`         FLOAT        NOT NULL,
                `y`         FLOAT        NOT NULL,
                `z`         FLOAT        NOT NULL,
                `heading`   FLOAT        NOT NULL,
                `created`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- Installs predating per-letter colour and the neon finish are missing those
        -- columns. MySQL has no portable ADD COLUMN IF NOT EXISTS, so look first.
        for column, ddl in pairs({
            colours   = 'VARCHAR(64) NULL',
            style     = 'VARCHAR(16) NULL',
            anim      = 'VARCHAR(16) NULL',
            animspeed = 'FLOAT NULL',
            spin      = 'FLOAT NULL',
            -- NULL means "use Config.RenderDistance", which is what every sign placed
            -- before the per-sign slider stores. Not defaulted to a number on purpose:
            -- baking 120 into old rows would freeze them at whatever the config said
            -- on the day this upgrade ran.
            renderdistance = 'FLOAT NULL',
        }) do
            local found = MySQL.query.await([[
                SELECT COLUMN_NAME FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = 'sd_signs' AND COLUMN_NAME = ?
            ]], { column })
            if not found or #found == 0 then
                MySQL.query.await(
                    ('ALTER TABLE `sd_signs` ADD COLUMN `%s` %s'):format(column, ddl))
                log.info('net', 'added the %s column to sd_signs', column)
            end
        end

        -- Multi-row signs are up to maxRows * maxLength characters plus separators,
        -- which no longer fits the original VARCHAR(64). Widening is a MODIFY, not an
        -- ADD, so the loop above cannot do it; check the current width first, because
        -- MODIFY on an already-wide column would rewrite the whole table on every
        -- single resource start.
        local width = MySQL.query.await([[
            SELECT CHARACTER_MAXIMUM_LENGTH AS len FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME = 'sd_signs' AND COLUMN_NAME = 'text'
        ]])
        local need = (config.Limits.maxRows or 1) * (config.Limits.maxLength or 24) * 2
        if width and width[1] and (tonumber(width[1].len) or 0) < need then
            MySQL.query.await(
                ('ALTER TABLE `sd_signs` MODIFY `text` VARCHAR(%d) NOT NULL'):format(need))
            log.info('net', 'widened sd_signs.text to VARCHAR(%d) for multi-row signs', need)
        end

        local rows = MySQL.query.await('SELECT * FROM `sd_signs`') or {}
        for _, r in ipairs(rows) do
            signs[r.id] = {
                id = r.id, owner = r.owner, text = r.text, colour = r.colour,
                colours = r.colours, style = r.style,
                anim = r.anim, animSpeed = r.animspeed, spin = r.spin,
                renderDistance = r.renderdistance,
                size = r.size, thickness = r.thickness, tracking = r.tracking,
                x = r.x, y = r.y, z = r.z, heading = r.heading,
            }
            local id = tonumber(r.id) or 0
            if id > nextId then nextId = id end
        end
        log.info('net', 'loaded %d sign(s) from the database', #rows)
        TriggerClientEvent('sd-signs:client:sync', -1, signs)
    end)
end

---Wrap load() so a database problem is reported instead of vanishing. A failed
---await inside a thread otherwise kills the thread with nothing in the console,
---which reads exactly like "persistence works but there is nothing saved".
local function safeLoad()
    local ok, err = pcall(load)
    if not ok then
        log.err('sign persistence failed to initialise: %s', tostring(err))
        log.err('signs will still work this session but will not survive a restart')
    end
end

---Every sign as a plain array, which is the shape the client sync expects.
---@return table[]
local function snapshot()
    local out = {}
    for _, rec in pairs(signs) do out[#out + 1] = rec end
    return out
end

RegisterNetEvent('sd-signs:server:requestSync', function()
    TriggerClientEvent('sd-signs:client:sync', source, snapshot())
end)

RegisterNetEvent('sd-signs:server:create', function(raw)
    local src = source
    if not allowed(src) then
        log.warn('player %s tried to place a sign without %s', tostring(src), tostring(config.Ace))
        return
    end

    -- Never trust the client's numbers: normalise clamps every field to Config.Limits.
    local record, reason = Sign.normalise(raw)
    if not record then
        log.debug('net', 'rejected sign from %s (%s)', tostring(src), reason or '?')
        return
    end

    local licence = licenceOf(src)
    local cap = config.Limits.maxPerPlayer
    if cap and ownedBy(licence) >= cap then
        TriggerClientEvent('ox_lib:notify', src,
            { type = 'error', description = ('You already own %d signs.'):format(cap) })
        return
    end

    nextId = nextId + 1
    record.id = nextId
    record.owner = licence
    signs[record.id] = record
    TriggerClientEvent('sd-signs:client:add', -1, record)
    log.info('net', 'player %s placed sign %d %q', tostring(src), record.id, record.text)

    if config.Persist then
        MySQL.insert([[
            INSERT INTO `sd_signs`
                (`id`,`owner`,`text`,`colour`,`colours`,`style`,`anim`,`animspeed`,`spin`,`renderdistance`,`size`,`thickness`,`tracking`,`x`,`y`,`z`,`heading`)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ]], {
            record.id, record.owner, record.text, record.colour, record.colours,
            record.style, record.anim, record.animSpeed, record.spin, record.renderDistance,
            record.size, record.thickness, record.tracking,
            record.x, record.y, record.z, record.heading,
        })
    end
end)

---Edit an existing sign in place. Position is optional: the builder saves appearance
---changes without moving anything, while "move" re-runs the placer and sends coords.
RegisterNetEvent('sd-signs:server:update', function(id, raw)
    local src = source
    if not allowed(src) then return end
    id = tonumber(id)
    if not id then return end
    local existing = signs[id]
    if not existing then return end

    -- Keep the current transform unless the payload carries a new one, then run the
    -- whole thing back through normalise so an edit is validated exactly like a create.
    --
    -- Copy the WHOLE payload rather than listing fields by hand. An explicit list
    -- silently drops anything added later, and it has now cost this resource three
    -- fields: style, the per-letter colours, and the per-sign render distance, each of
    -- which edited fine in the builder and then quietly reverted on save.
    --
    -- Copying everything is safe because normalise() is the whitelist: it reads only
    -- the fields it knows and returns a fresh table, so extra keys go nowhere. `id`
    -- and `owner` are set from the server's own record below for the same reason.
    local merged = {}
    for k, v in pairs(raw or {}) do merged[k] = v end
    merged.x = (raw and raw.x) or existing.x
    merged.y = (raw and raw.y) or existing.y
    merged.z = (raw and raw.z) or existing.z
    merged.heading = (raw and raw.heading) or existing.heading
    local record, reason = Sign.normalise(merged)
    if not record then
        log.debug('net', 'rejected edit of sign %d from %s (%s)', id, tostring(src), reason or '?')
        return
    end

    record.id = id
    record.owner = existing.owner        -- editing never transfers ownership
    signs[id] = record
    TriggerClientEvent('sd-signs:client:add', -1, record)
    log.info('net', 'player %s edited sign %d %q', tostring(src), id, record.text)

    if config.Persist then
        MySQL.query([[
            UPDATE `sd_signs`
               SET `text` = ?, `colour` = ?, `colours` = ?, `style` = ?,
                   `anim` = ?, `animspeed` = ?, `spin` = ?, `renderdistance` = ?, `size` = ?,
                   `thickness` = ?, `tracking` = ?, `x` = ?, `y` = ?, `z` = ?, `heading` = ?
             WHERE `id` = ?
        ]], {
            record.text, record.colour, record.colours, record.style,
            record.anim, record.animSpeed, record.spin, record.renderDistance, record.size,
            record.thickness, record.tracking, record.x, record.y, record.z, record.heading, id,
        })
    end
end)

RegisterNetEvent('sd-signs:server:remove', function(id)
    local src = source
    if type(id) ~= 'number' then return end
    local rec = signs[id]
    if not rec then return end
    if not allowed(src) then return end

    signs[id] = nil
    TriggerClientEvent('sd-signs:client:remove', -1, id)
    log.info('net', 'player %s removed sign %d', tostring(src), id)
    if config.Persist then
        MySQL.query('DELETE FROM `sd_signs` WHERE `id` = ?', { id })
    end
end)

-- Load on a short delay rather than off onResourceStart: oxmysql may not have
-- finished coming up when this resource starts, and a query issued too early is
-- exactly the kind of failure that leaves no trace.
CreateThread(function()
    Wait(1000)
    safeLoad()
end)
