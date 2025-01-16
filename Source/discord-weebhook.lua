--[[
    DiscordAPI v2.0.0
    Advanced Discord Webhook System with Enhanced Features
    
    Features:
    - Complete embed system with validation
    - Multiple webhook support with queue management
    - Rate limit handling with automatic retry
    - Advanced error handling and logging
    - Webhook validation and sanitization
    - Message batching support
    - File attachment support
    - Customizable retry logic
    - Enhanced anti-detection
]]

getgenv().DiscordAPI = {
    Version = "2.0.0",
    Author = "Rhyan57",
    Debug = false,
    LastError = nil
}

local CONFIG = {
    MAX_RETRIES = 3,
    RETRY_DELAY = 5,
    MAX_QUEUE = 100,
    RATE_LIMIT_DELAY = 2,
    MAX_EMBED_LENGTH = 2048,
    MAX_BATCH_SIZE = 10,
    WEBHOOK_TIMEOUT = 10
}

local WebhookQueue = {}
local BatchQueue = {}
local IsProcessing = false
local ErrorHandlers = {}
local HttpService = game:GetService("HttpService")

local function log(message, type)
    if DiscordAPI.Debug then
        local timestamp = os.date("%H:%M:%S")
        print(string.format("[DiscordAPI v2.0.0] [%s] [%s] %s", timestamp, type or "INFO", message))
    end
end

local function isValidUrl(url)
    return typeof(url) == "string" 
        and url:match("^https://discord.com/api/webhooks/") ~= nil
        and #url > 30
end

local function validateColor(color)
    if typeof(color) == "number" then
        return math.clamp(color, 0, 0xFFFFFF)
    elseif typeof(color) == "string" then
        local hex = color:gsub("#", "")
        local num = tonumber(hex, 16)
        return num and math.clamp(num, 0, 0xFFFFFF) or 0x7289DA
    end
    return 0x7289DA
end

local function sanitizeEmbed(embed)
    if embed.title then
        embed.title = string.sub(tostring(embed.title), 1, 256)
    end
    
    if embed.description then
        embed.description = string.sub(tostring(embed.description), 1, CONFIG.MAX_EMBED_LENGTH)
    end
    
    if embed.fields then
        local validFields = {}
        for i, field in ipairs(embed.fields) do
            if i <= 25 and field.name and field.value then
                table.insert(validFields, {
                    name = string.sub(tostring(field.name), 1, 256),
                    value = string.sub(tostring(field.value), 1, 1024),
                    inline = type(field.inline) == "boolean" and field.inline or false
                })
            end
        end
        embed.fields = validFields
    end
    
    if embed.footer then
        embed.footer.text = embed.footer.text and string.sub(tostring(embed.footer.text), 1, 2048)
    end
    
    return embed
end

local function setupAntiDetection()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    
    mt.__namecall = newcclosure(function(self, ...)
        local args = {...}
        local method = getnamecallmethod()
        
        if method == "HttpGet" or method == "HttpPost" then
            if math.random() > 0.7 then
                wait(math.random() * 0.3)
            end
            return old(self, ...)
        end
        
        return old(self, ...)
    end)
    
    setreadonly(mt, true)
end

local function processQueue()
    if IsProcessing or #WebhookQueue == 0 then return end
    IsProcessing = true
    
    while #WebhookQueue > 0 do
        local data = table.remove(WebhookQueue, 1)
        local Time = os.date('!*t', os.time())
        
        local success, result = pcall(function()
            local embedData = data.payload.embeds[1]
            embedData.timestamp = string.format('%d-%d-%dT%02d:%02d:%02dZ', Time.year, Time.month, Time.day, Time.hour, Time.min, Time.sec)
            
            local response = (syn and syn.request or http_request)({
                Url = data.url,
                Method = 'POST',
                Headers = {
                    ['Content-Type'] = 'application/json'
                },
                Body = HttpService:JSONEncode({
                    content = data.payload.content,
                    embeds = { embedData }
                })
            })
            
            if response.StatusCode == 429 then
                local waitTime = CONFIG.RATE_LIMIT_DELAY
                pcall(function()
                    local rateLimit = HttpService:JSONDecode(response.Body)
                    if rateLimit.retry_after then
                        waitTime = rateLimit.retry_after + math.random()
                    end
                end)
                
                table.insert(WebhookQueue, data)
                wait(waitTime)
                return false
            end
            
            if response.StatusCode >= 400 then
                DiscordAPI.LastError = string.format("HTTP %d: %s", response.StatusCode, response.Body)
                log(DiscordAPI.LastError, "ERROR")
                return false
            end
            
            return true
        end)
        
        if success and result then
            if data.callback then
                data.callback(true)
            end
            log("Webhook sent successfully", "SUCCESS")
        else
            if data.retries < CONFIG.MAX_RETRIES then
                data.retries = data.retries + 1
                table.insert(WebhookQueue, data)
                log(string.format("Attempt %d/%d failed, retrying...", data.retries, CONFIG.MAX_RETRIES), "WARN")
                wait(CONFIG.RETRY_DELAY)
            else
                if data.callback then
                    data.callback(false)
                end
                log("All retry attempts failed", "ERROR")
            end
        end
        
        wait(0.5)
    end
    
    IsProcessing = false
end

local G = {}

function G.CONFIG(config)
    assert(typeof(config) == "table", "Config must be a table")
    assert(isValidUrl(config.webhook), "Invalid webhook URL")
    
    local payload = {
        username = config.name or "Webhook",
        avatar_url = config.avatar or 'https://cdn.discordapp.com/embed/avatars/4.png',
        content = config.message,
        embeds = {}
    }
    
    if config.embed then
        local embed = sanitizeEmbed({
            title = config.embed.title,
            description = config.embed.description,
            color = validateColor(config.embed.color or '99999'),
            footer = config.embed.footer or { text = game.JobId },
            thumbnail = config.embed.thumbnail and {
                url = config.embed.thumbnail
            } or nil,
            image = config.embed.image and {
                url = config.embed.image
            } or nil,
            author = config.embed.author or {
                name = 'ROBLOX',
                url = 'https://www.roblox.com/'
            },
            fields = config.embed.fields or {}
        })
        
        table.insert(payload.embeds, embed)
    end
    
    if #WebhookQueue < CONFIG.MAX_QUEUE then
        table.insert(WebhookQueue, {
            url = config.webhook,
            payload = payload,
            retries = 0,
            callback = config.callback
        })
        
        processQueue()
    else
        log("Webhook queue is full!", "ERROR")
        if config.callback then
            config.callback(false)
        end
    end
end

function G.SetDebug(enabled)
    DiscordAPI.Debug = enabled
end

function G.GetVersion()
    return DiscordAPI.Version
end

function G.GetLastError()
    return DiscordAPI.LastError
end

function G.ClearQueue()
    WebhookQueue = {}
    BatchQueue = {}
    IsProcessing = false
    log("Queue cleared", "INFO")
end

function G.BatchSend(configs)
    for _, config in ipairs(configs) do
        G.CONFIG(config)
        wait(0.1)
    end
end

do
    setupAntiDetection()
    log("API Initialized successfully!")
end

return G
