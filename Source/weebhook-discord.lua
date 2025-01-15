--[[
    DiscordAPI v1.0.1
    Sistema avançado de Webhooks para Discord
    Recursos:
    - Sistema completo de embeds
    - Suporte a múltiplos webhooks
    - Sistema de filas para evitar rate limits
    - Callbacks e eventos
    - Sistema de logs
    - Anti-detecção integrado
]]

getgenv().G = {}
getgenv().DiscordAPI = {
    Version = "1.0.1",
    Author = "Rhyan57",
    Debug = false
}

local CONFIG = {
    MAX_RETRIES = 3,
    RETRY_DELAY = 5,
    MAX_QUEUE = 50,
    RATE_LIMIT_DELAY = 2
}

local WebhookQueue = {}
local IsProcessing = false

local HttpService = game:GetService("HttpService")

local function log(message, type)
    if DiscordAPI.Debug then
        print(string.format("[DiscordAPI - Msdoors] [%s] %s", type or "INFO", message))
    end
end

local function isValidUrl(url)
    return typeof(url) == "string" and url:match("^https://discord.com/api/webhooks/") ~= nil
end

local function validateColor(color)
    if typeof(color) == "number" then
        return math.clamp(color, 0, 0xFFFFFF)  -- Ensure color is within valid range
    elseif typeof(color) == "string" then
        local hex = color:gsub("#", "")
        return tonumber(hex, 16) or 0x7289DA
    end
    return 0x7289DA 
end

local function sanitizePayload(payload)
    -- Ensure all required fields exist
    payload.username = payload.username or "Webhook"
    payload.avatar_url = payload.avatar_url or ""
    payload.content = payload.content or ""
    
    -- Validate embeds
    if payload.embeds and #payload.embeds > 0 then
        for i, embed in ipairs(payload.embeds) do
            -- Ensure required embed fields
            embed.title = embed.title or ""
            embed.description = embed.description or ""
            embed.color = embed.color or 0x7289DA
            
            -- Validate fields array
            if embed.fields then
                for j, field in ipairs(embed.fields) do
                    field.name = field.name or "Field"
                    field.value = field.value or "Value"
                    field.inline = type(field.inline) == "boolean" and field.inline or false
                end
            end
        end
    end
    
    return payload
end

local function processQueue()
    if IsProcessing or #WebhookQueue == 0 then return end
    IsProcessing = true
    
    local function processNext()
        local data = table.remove(WebhookQueue, 1)
        if data then
            local success, result = pcall(function()
                -- Sanitize payload before sending
                data.payload = sanitizePayload(data.payload)
                
                -- Convert payload to JSON
                local jsonPayload = HttpService:JSONEncode(data.payload)
                
                -- Make the request
                local response = syn.request({
                    Url = data.url,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = jsonPayload
                })
                
                -- Handle rate limiting
                if response.StatusCode == 429 then
                    local waitTime = CONFIG.RATE_LIMIT_DELAY
                    -- Try to parse rate limit headers if available
                    pcall(function()
                        local rateLimit = HttpService:JSONDecode(response.Body)
                        if rateLimit.retry_after then
                            waitTime = rateLimit.retry_after + 0.5
                        end
                    end)
                    
                    table.insert(WebhookQueue, 1, data)  -- Re-insert at start of queue
                    wait(waitTime)
                    return false
                end
                
                return response.StatusCode >= 200 and response.StatusCode < 300
            end)
            
            if success and result then
                if data.callback then
                    data.callback(true)
                end
                log("Webhook enviado com sucesso!", "SUCCESS")
            else
                if data.retries < CONFIG.MAX_RETRIES then
                    data.retries = data.retries + 1
                    table.insert(WebhookQueue, data)
                    log(string.format("Tentativa %d de %d falhou, tentando novamente...", data.retries, CONFIG.MAX_RETRIES), "WARN")
                else
                    if data.callback then
                        data.callback(false)
                    end
                    log("Todas as tentativas falharam!", "ERROR")
                end
            end
            
            wait(0.5)  -- Prevent spamming
            processNext()
        else
            IsProcessing = false
        end
    end
    
    processNext()
end

function G.CONFIG(config)
    assert(typeof(config) == "table", "Config deve ser uma tabela")
    assert(isValidUrl(config.webhook), "URL do webhook inválida")
    
    local payload = {
        username = config.name,
        avatar_url = config.avatar,
        content = config.message,
        embeds = {}
    }
    
    if config.embed then
        local embed = {
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
        }
        
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
        log("Fila de webhooks cheia!", "ERROR")
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

-- Initialize
do
    log("API Inicializada com sucesso!")
end

return G
