local HttpService = game:GetService("HttpService")

local config = {
    webhookUrl = "https://discord.com/api/webhooks/1323101801721106443/Nsf1YFyNmHwWbf1LsejwZFxVpCt6YsgxpK3UfeTstBV0gZ1dQLiwNPO5xBsgu7dHyyOA", -- Substitua pela sua webhook
    botName = "Rhyan57",
    botAvatar = "https://cdn.discordapp.com/embed/avatars/4.png",
    rateLimitCooldown = 2 
}

local function sendWebhook(embed)
    local payload = {
        content = "**Aviso Automático**: Sistema Webhook Executado.",
        username = config.botName,
        avatar_url = config.botAvatar,
        embeds = { embed }
    }

    local request = (syn and syn.request or http_request) or request or http and http.request
    if not request then
        error("Nenhuma função de solicitação HTTP compatível foi encontrada.")
    end

    local response = request({
        Url = config.webhookUrl,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json"
        },
        Body = HttpService:JSONEncode(payload)
    })

    if response and response.StatusCode == 204 then
        print("[Sucesso] Webhook enviado com sucesso!")
    else
        warn("[Erro] Falha ao enviar webhook. Detalhes:", response and response.StatusMessage or "Desconhecido")
    end
end

return {
    sendWebhook = sendWebhook,
    config = config
}
