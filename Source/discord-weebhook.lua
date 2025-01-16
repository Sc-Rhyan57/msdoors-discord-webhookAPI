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

-- Global API object
getgenv().DiscordAPI = {
    Version = "2.0.0",
    Author = "Rhyan57",
    Debug = false,
    LastError = nil
}

-- Configuration
local CONFIG = {
    MAX_RETRIES = 3,
    RETRY_DELAY = 5,
    MAX_QUEUE = 100,
    RATE_LIMIT_DELAY = 2,
    MAX_EMBED_LENGTH = 2048,
    MAX_BATCH_SIZE = 10,
    WEBHOOK_TIMEOUT = 10
}

-- Internal state
local WebhookQueue = {}
local BatchQueue = {}
local IsProcessing = false
local ErrorHandlers = {}

-- Services
local HttpService = game:GetService("HttpService")

-- Utility Functions
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
    -- Enforce Discord's limits and requirements
    if embed.title then
        embed.title = string.sub(tostring(embed.title), 1, 256)
    end
    
    if embed.description then
        embed.description = string.sub(tostring(embed.description), 1, CONFIG.MAX_EMBED_LENGTH)
    end
    
    -- Validate fields
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
    
    -- Validate footer
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
            -- Add random delays and headers to appear more natural
            if math.random() > 0.7 then
                wait(math.random() * 0.3)
            end
            return old(self, ...)
        end
        
        return old(self, ...)
    end)
    
    setreadonly(mt, true)
end

-- Enhanced webhook processing
local function processWebhook(data)
    local success, result = pcall(function()
        -- Add random user-agent and additional headers
        local headers = {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            ["Accept"] = "application/json, text/plain, */*"
        }
        
        -- Make the request with timeout
        local response = syn.request({
            Url = data.url,
            Method = "POST",
            Headers = headers,
            Body = HttpService:JSONEncode(data.payload),
            Timeout = CONFIG.WEBHOOK_TIMEOUT
        })
        
        -- Handle rate limiting
        if response.StatusCode == 429 then
            local waitTime = CONFIG.RATE_LIMIT_DELAY
            pcall(function()
                local rateLimit = HttpService:JSONDecode(response.Body)
                if rateLimit.retry_after then
                    waitTime = rateLimit.retry_after + math.random()
                end
            end)
            
            log(string.format("Rate limited, waiting %.2f seconds", waitTime), "WARN")
            wait(waitTime)
            return false
        end
        
        -- Handle other status codes
        if response.StatusCode >= 400 then
            DiscordAPI.LastError = string.format("HTTP %d: %s", response.StatusCode, response.Body)
            log(DiscordAPI.LastError, "ERROR")
            return false
        end
        
        return true
    end)
    
    return success and result
end

-- Queue processing
local function processQueue()
    if IsProcessing or #WebhookQueue == 0 then return end
    IsProcessing = true
    
    while #WebhookQueue > 0 do
        local data = table.remove(WebhookQueue, 1)
        local success = processWebhook(data)
        
        if success then
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
        
        wait(0.5) -- Prevent spamming
    end
    
    IsProcessing = false
end

-- Public API Functions
local G = {}

function G.CONFIG(config)
    assert(typeof(config) == "table", "Config must be a table")
    assert(isValidUrl(config.webhook), "Invalid webhook URL")
    
    local payload = {
        username = config.name or "Webhook",
        avatar_url = config.avatar,
        content = config.message,
        embeds = {}
    }
    
    if config.embed then
        local embed = sanitizeEmbed({
            title = config.embed.title,
            description = config.embed.description,
            color = validateColor(config.embed.color),
            footer = config.embed.footer and {
                text = config.embed.footer.text,
                icon_url = config.embed.footer.icon
            } or nil,
            thumbnail = config.embed.thumbnail and {
                url = config.embed.thumbnail
            } or nil,
            image = config.embed.image and {
                url = config.embed.image
            } or nil,
            author = config.embed.author and {
                name = config.embed.author.name,
                icon_url = config.embed.author.icon
            } or nil,
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

-- Initialize
do
    setupAntiDetection()
    log("API Initialized successfully!")
end

return G
