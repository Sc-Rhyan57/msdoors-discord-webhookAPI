-- Configurações
getgenv().G = {}

-- Função principal
function G.CONFIG(config)
    local HttpService = game:GetService("HttpService")
    
    -- Validar webhook
    if not config.webhook then
        warn("Webhook URL é obrigatória!")
        return
    end
    
    -- Criar payload
    local payload = {
        username = config.name or "Webhook",
        content = config.message or "",
        avatar_url = config.avatar,
        embeds = {{
            title = config.title or "",
            description = config.description or "",
            color = tonumber(config.color:gsub("#", ""), 16) or 16711680, -- Vermelho por padrão
            thumbnail = {
                url = config.thumbnail
            },
            image = {
                url = config.image
            }
        }}
    }
    
    -- Tentar enviar
    local success, response = pcall(function()
        local data = HttpService:JSONEncode(payload)
        return syn.request({
            Url = config.webhook,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = data
        })
    end)
    
    -- Verificar resultado
    if success then
        print("Webhook enviado com sucesso!")
    else
        warn("Erro ao enviar webhook:", response)
    end
end

return G
