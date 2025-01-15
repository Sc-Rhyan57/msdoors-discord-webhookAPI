--[[
    DiscordAPI v1.0
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
    Version = "1.0.0",
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

local function setupAntiDetection()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    
    mt.__namecall = newcclosure(function(self, ...)
        local args = {...}
        local method = getnamecallmethod()
        
        if method == "HttpGet" or method == "HttpPost" then
            return old(self, ...)
        end
        
        return old(self, ...)
    end)
end

local function isValidUrl(url)
    return typeof(url) == "string" and url:match("^https://discord.com/api/webhooks/") ~= nil
end

local function validateColor(color)
    if typeof(color) == "number" then
        return color
    elseif typeof(color) == "string" then
        return tonumber(color:gsub("#", ""), 16)
    end
    return 0x7289DA 
end

local function processQueue()
    if IsProcessing or #WebhookQueue == 0 then return end
    IsProcessing = true
    
    local function processNext()
        local data = table.remove(WebhookQueue, 1)
        if data then
            local success, result = pcall(function()
                local response = syn.request({
                    Url = data.url,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = HttpService:JSONEncode(data.payload)
                })
                
                if response.StatusCode == 429 then
                    table.insert(WebhookQueue, data)
                    wait(CONFIG.RATE_LIMIT_DELAY)
                end
                
                return response.StatusCode >= 200 and response.StatusCode < 300
            end)
            
            if success and result then
                if data.callback then
                    data.callback(true)
                end
            else
                if data.retries < CONFIG.MAX_RETRIES then
                    data.retries = data.retries + 1
                    table.insert(WebhookQueue, data)
                else
                    if data.callback then
                        data.callback(false)
                    end
                end
            end
            
            wait(0.5)
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
        username = config.name or "Rhyan57",
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

do
    setupAntiDetection()
    log("API Inicializada com sucesso!")
end

return G
