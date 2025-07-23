Config = Config or {}

local function isCategoryEnabled(category)
    if not Config.Debug then
        return false
    end

    if not Config.DebugCategories then
        return false
    end

    if category == nil then
        return true
    end

    if Config.DebugCategories[category] == nil then
        return false
    end

    return Config.DebugCategories[category]
end

local function getCategoryColor(category)
    if not Config.DebugColors then
        return "^7"
    end

    return Config.DebugColors[category] or "^7"
end

function Log(category, message, ...)
    if not isCategoryEnabled(category) then
        return
    end

    local color = getCategoryColor(category)
    local formattedMessage = message

    if select('#', ...) > 0 then
        formattedMessage = string.format(message, ...)
    end

    print(string.format("%s[%s]^0 %s", color, category or "GENERAL", formattedMessage))
end

function LogSeparator(category, char)
    if not isCategoryEnabled(category) then
        return
    end

    local color = getCategoryColor(category)
    local separator = string.rep(char or "=", 60)
    print(string.format("%s%s^0", color, separator))
end

function LogBlock(category, title, lines)
    if not isCategoryEnabled(category) then
        return
    end

    local color = getCategoryColor(category)

    LogSeparator(category)
    print(string.format("%s[%s]^0 %s", color, category or "GENERAL", title))
    LogSeparator(category, "-")

    for _, line in ipairs(lines or {}) do
        print(string.format("%s[%s]^0 %s", color, category or "GENERAL", line))
    end

    LogSeparator(category)
end
